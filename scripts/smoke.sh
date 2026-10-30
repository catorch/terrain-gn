#!/usr/bin/env bash
# End-to-end smoke test of the Phase 1 API against a running server (dev OTP 000000).
# Usage: API=http://localhost:4100/v1 ADMIN_API_KEY=... scripts/smoke.sh
set -euo pipefail
API=${API:-http://localhost:4100/v1}
KEY=${ADMIN_API_KEY:?set ADMIN_API_KEY}
AGENT=${AGENT_EMAIL:-agent@terrain.gn}
RUN=$RANDOM
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; exit 1; }
json() { curl -s -H 'content-type: application/json' "$@"; }
status() { curl -s -o /dev/null -w '%{http_code}' -H 'content-type: application/json' "$@"; }

login() {
  json -X POST "$API/auth/otp/start" -d "{\"phone\":\"$1\"}" >/dev/null
  json -X POST "$API/auth/otp/verify" -d "{\"phone\":\"$1\",\"code\":\"000000\"}" | jq -r .accessToken
}
# Corners of a w×h metre rectangle at (x, y) metres from a point in Ratoma, Conakry, shifted per run.
rect() { jq -cn --argjson x "$1" --argjson y "$2" --argjson w "$3" --argjson h "$4" --argjson run "$RUN" '
  (($run % 1000) * 60) as $o | (-13.6) as $lon | 9.6 as $lat | (110610) as $my | (109790) as $mx |
  [[$x,$y],[$x+$w,$y],[$x+$w,$y+$h],[$x,$y+$h]] | map([$lon + (.[0]+$o)/$mx, $lat + .[1]/$my])'; }
parcel() { jq -cn --argjson corners "$1" '{boundary:{corners:$corners}, title:"Terrain smoke test", region:"conakry", prefecture:"Ratoma", locality:"Kipé", priceGnf:150000000}'; }

[ "$(status "$API/ready")" = 200 ] && pass "ready" || fail "ready"
SELLER=$(login "+22462$(printf '%07d' $((RUN * 10 + 1)))")
BUYER=$(login "+3361$(printf '%07d' $((RUN * 10 + 2)))")
[ -n "$SELLER" ] && [ "$SELLER" != null ] && pass "OTP login" || fail "OTP login"

CHECK=$(json -X POST "$API/parcels/check" -H "authorization: Bearer $SELLER" -d "{\"corners\":$(rect 0 0 20 25)}")
[ "$(jq -r .ok <<<"$CHECK")" = true ] && pass "dry-run check ($(jq -r .areaM2 <<<"$CHECK") m²)" || fail "dry-run check: $CHECK"

CREATED=$(json -X POST "$API/parcels" -H "authorization: Bearer $SELLER" -H "idempotency-key: smoke-$RUN" -d "$(parcel "$(rect 0 0 20 25)")")
ID=$(jq -r .id <<<"$CREATED"); CODE=$(jq -r .code <<<"$CREATED")
[ "$ID" != null ] && pass "create $CODE" || fail "create: $CREATED"

OVERLAP=$(json -X POST "$API/parcels" -H "authorization: Bearer $BUYER" -d "$(parcel "$(rect 5 0 20 25)")")
[ "$(jq -r .code <<<"$OVERLAP")" = PARCEL_OVERLAP ] && [ "$(jq -r '.conflicts[0].code' <<<"$OVERLAP")" = "$CODE" ] && pass "overlap rejected with $CODE" || fail "overlap: $OVERLAP"

[ "$(status -X POST "$API/parcels" -H "authorization: Bearer $BUYER" -d "$(parcel "$(rect 20 0 20 25)")")" = 201 ] && pass "edge-touching neighbour accepted" || fail "neighbour"

[ "$(status "$API/parcels/$ID")" = 404 ] && pass "unverified parcel hidden" || fail "unverified parcel visible"
VERIFY=$(json -X POST "$API/admin/parcels/$ID/verification" -H "authorization: Bearer $KEY" -H "x-actor-email: $AGENT" -d '{"verified":true,"note":"smoke"}')
[ "$(jq -r .verified <<<"$VERIFY")" = true ] && pass "agent verified" || fail "verify: $VERIFY"
[ "$(curl -s "$API/parcels/$ID" | jq -r .verified)" = true ] && pass "badge visible on detail" || fail "badge"
curl -s "$API/parcels?region=conakry" | jq -e --argjson id "$ID" '.items | map(.id) | index($id) != null' >/dev/null && pass "listed" || fail "not listed"

URL=$(json -X POST "$API/parcels/$ID/contact" -H "authorization: Bearer $BUYER" | jq -r .url)
TEXT=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1].split("text=")[1]))' "$URL")
grep -q "terrain $CODE" <<<"$TEXT" && pass "WhatsApp link (FR): ${URL%%\?*}" || fail "whatsapp: $TEXT"

[ "$(json -X POST "$API/parcels/check" -H "authorization: Bearer $SELLER" -d '{"corners":[[1,2]]}' | jq -r .code)" = VALIDATION_FAILED ] && pass "validation error code" || fail "validation"
[ "$(curl -s "$API/parcels/abc" | jq -r .code)" = BAD_REQUEST ] && pass "Nest errors carry a code" || fail "nest error code"
GZIP=$(curl -s -o /dev/null -w '%{size_download}' -H 'accept-encoding: gzip' "$API/parcels"); PLAIN=$(curl -s -o /dev/null -w '%{size_download}' "$API/parcels")
pass "list response ${PLAIN}B plain, ${GZIP}B with gzip (compression starts above 1 KB)"
echo "Smoke test passed."
