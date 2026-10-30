#!/usr/bin/env bash
set -euo pipefail
trap 'printf "ERROR: demo photo seeding failed at line %s\n" "$LINENO" >&2; exit 1' ERR

API="${API:-http://localhost:4100/v1}"
API="${API%/}"
SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
PHOTO_DIR="$SCRIPT_DIR/demo-photos"

# Check 2xx explicitly: curl --fail alone also accepts redirects.
request() {
  local response status
  if ! response="$(curl --silent --show-error --fail-with-body \
    --connect-timeout 10 --max-time 120 \
    --write-out $'\n%{http_code}' "$@")"; then
    printf 'ERROR: request failed: %s\n' "$response" >&2
    return 1
  fi
  status="${response##*$'\n'}"
  response="${response%$'\n'*}"
  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
    printf 'ERROR: HTTP %s: %s\n' "$status" "$response" >&2
    return 1
  fi
  printf '%s' "$response"
}

declare -A sizes
for name in kipe-walled-plot.jpg kipe-boundary-marker.jpg \
  lambanyi-roadside-plot.jpg kagbelen-flat-plot.jpg \
  maneah-farmland.jpg koba-seaside.jpg; do
  [[ -r "$PHOTO_DIR/$name" ]] || {
    printf 'ERROR: missing photo: %s\n' "$PHOTO_DIR/$name" >&2
    exit 1
  }
  # curl's file transport counts exact binary bytes without wc/stat.
  bytes="$(curl --silent --show-error --output /dev/null \
    --write-out '%{size_download}' "file://$PHOTO_DIR/$name")"
  [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 0 && bytes <= 300000 )) || {
    printf 'ERROR: invalid photo size for %s: %s bytes\n' "$name" "$bytes" >&2
    exit 1
  }
  sizes["$name"]="$bytes"
done

for phone in +224620000101 +224660000102; do
  auth="$(request --request POST "$API/auth/otp/verify" \
    --header 'content-type: application/json' \
    --data "$(jq -nc --arg phone "$phone" '{phone: $phone, code: "000000"}')")"
  token="$(jq -er '.accessToken | strings | select(length > 0)' <<< "$auth")"
  parcels="$(request "$API/me/parcels" --header "authorization: Bearer $token")"
  jq -e '.items | type == "array"' <<< "$parcels" > /dev/null
  mapfile -t items < <(jq -c '.items[]' <<< "$parcels")

  for parcel in "${items[@]}"; do
    title="$(jq -er '.title | strings' <<< "$parcel")"
    case "$title" in
      $'Terrain cl\u00f4tur\u00e9 avec titre foncier')
        files=(kipe-walled-plot.jpg kipe-boundary-marker.jpg) ;;
      $'Parcelle viabilis\u00e9e proche route')
        files=(lambanyi-roadside-plot.jpg) ;;
      'Terrain plat, quartier calme') files=(kagbelen-flat-plot.jpg) ;;
      'Grand terrain agricole') files=(maneah-farmland.jpg) ;;
      'Terrain en bord de mer') files=(koba-seaside.jpg) ;;
      *) continue ;;
    esac
    id="$(jq -er '.id | tostring | select(test("^[0-9]+$"))' <<< "$parcel")"
    code="$(jq -er '.code | strings' <<< "$parcel")"
    detail="$(request "$API/parcels/$id" --header "authorization: Bearer $token")"
    photo_count="$(jq -er '.photos | arrays | length' <<< "$detail")"
    if (( photo_count > 0 )); then
      printf '%s | %s | skipped, already has photos\n' "$code" "$title"
      continue
    fi

    uploaded=0
    for name in "${files[@]}"; do
      upload="$(request --request POST "$API/parcels/$id/documents" \
        --header "authorization: Bearer $token" \
        --header 'content-type: application/json' \
        --data "$(jq -nc --argjson size "${sizes[$name]}" \
          '{kind: "photo", contentType: "image/jpeg", sizeBytes: $size}')")"
      document_id="$(jq -er '.documentId | tostring | select(test("^[0-9]+$"))' <<< "$upload")"
      upload_url="$(jq -er '.uploadUrl | strings | select(length > 0)' <<< "$upload")"
      jq -e '.headers | type == "object" and
        all(.[]; type == "string") and
        (to_entries | any(.[]; (.key | ascii_downcase) == "content-type" and .value == "image/jpeg"))' \
        <<< "$upload" > /dev/null
      mapfile -t headers < <(jq -r '.headers | to_entries[] | "\(.key): \(.value)"' <<< "$upload")
      put_headers=()
      for header in "${headers[@]}"; do
        put_headers+=(--header "$header")
      done
      request --request PUT "$upload_url" "${put_headers[@]}" \
        --data-binary "@$PHOTO_DIR/$name" > /dev/null
      complete="$(request --request POST "$API/parcels/$id/documents/$document_id/complete" \
        --header "authorization: Bearer $token")"
      jq -e '.uploaded == true' <<< "$complete" > /dev/null
      uploaded=$((uploaded + 1))
    done
    printf '%s | %s | %s photos uploaded\n' "$code" "$title" "$uploaded"
  done
done
