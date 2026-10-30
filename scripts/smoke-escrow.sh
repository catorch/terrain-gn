#!/usr/bin/env bash
# End-to-end escrow run against a local API wired to scripts/fake-cinetpay.mjs.
# Needs staff rows agent@terrain.gn (agent) and admin@terrain.gn (admin): see scripts/seed-demo.sql.
# Usage: API=http://localhost:4100/v1 ADMIN_API_KEY=... scripts/smoke-escrow.sh
set -euo pipefail
API=${API:-http://localhost:4100/v1}
KEY=${ADMIN_API_KEY:?set ADMIN_API_KEY}
RUN=$RANDOM
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; exit 1; }
json() { curl -s -H 'content-type: application/json' "$@"; }
staff() { json -H "authorization: Bearer $KEY" -H "x-actor-email: $1" "${@:2}"; }
login() { json -X POST "$API/auth/otp/verify" -d "{\"phone\":\"$1\",\"code\":\"000000\"}"; }

SELLER_PHONE="+22462$(printf '%07d' $((RUN * 10 + 5)))"; BUYER_PHONE="+22466$(printf '%07d' $((RUN * 10 + 6)))"
SELLER_SESSION=$(login "$SELLER_PHONE"); BUYER_SESSION=$(login "$BUYER_PHONE")
SELLER=$(jq -r .accessToken <<<"$SELLER_SESSION"); BUYER=$(jq -r .accessToken <<<"$BUYER_SESSION")
SELLER_ID=$(jq -r .user.id <<<"$SELLER_SESSION"); BUYER_ID=$(jq -r .user.id <<<"$BUYER_SESSION")
json -X PATCH "$API/me" -H "authorization: Bearer $SELLER" -d "{\"payout\":{\"phone\":\"$SELLER_PHONE\",\"method\":\"OM_GN\"}}" >/dev/null
json -X PATCH "$API/me" -H "authorization: Bearer $BUYER" -d "{\"payout\":{\"phone\":\"$BUYER_PHONE\",\"method\":\"MTN_GN\"}}" >/dev/null
pass "seller and buyer signed in with payout wallets"

CORNERS=$(jq -cn --argjson run "$RUN" '(($run % 1000) * 60) as $o | [[0,0],[20,0],[20,25],[0,25]] | map([-13.62 + (.[0] + $o) / 109790, 9.65 + .[1] / 110610])')
PARCEL=$(json -X POST "$API/parcels" -H "authorization: Bearer $SELLER" -d "{\"boundary\":{\"corners\":$CORNERS},\"title\":\"Terrain escrow test\",\"region\":\"conakry\",\"prefecture\":\"Ratoma\",\"locality\":\"Lambanyi\",\"priceGnf\":200000000,\"depositGnf\":1000000}")
ID=$(jq -r .id <<<"$PARCEL"); [ "$ID" != null ] || fail "create parcel: $PARCEL"
staff agent@terrain.gn -X POST "$API/admin/parcels/$ID/verification" -d '{"verified":true}' >/dev/null
staff agent@terrain.gn -X POST "$API/admin/users/$SELLER_ID/payout-verification" -d "{\"verified\":true,\"payoutPhone\":\"$SELLER_PHONE\"}" >/dev/null
staff agent@terrain.gn -X POST "$API/admin/users/$BUYER_ID/payout-verification" -d "{\"verified\":true,\"payoutPhone\":\"$BUYER_PHONE\"}" >/dev/null
pass "agent verified $(jq -r .code <<<"$PARCEL") and both wallets"

RES=$(json -X POST "$API/parcels/$ID/reservations" -H "authorization: Bearer $BUYER" -H "idempotency-key: escrow-$RUN")
RID=$(jq -r .id <<<"$RES"); PAY_URL=$(jq -r .paymentUrl <<<"$RES")
[ "$(jq -r .status <<<"$RES")" = pending_payment ] && pass "reservation $RID pending, checkout $PAY_URL" || fail "reserve: $RES"
[ "$(json -X POST "$API/parcels/$ID/reservations" -H "authorization: Bearer $BUYER" -H "idempotency-key: escrow-$RUN" | jq -r .id)" = "$RID" ] && pass "retry with same Idempotency-Key returns the same reservation" || fail "idempotency"

curl -s -o /dev/null -X POST "$PAY_URL/pay"
[ "$(json "$API/reservations/$RID" -H "authorization: Bearer $BUYER" | jq -r .status)" = held ] && pass "paid: deposit held" || fail "not held"
[ "$(curl -s "$API/parcels/$ID" | jq -r .status)" = reserved ] && pass "parcel shows as reserved" || fail "parcel not reserved"

FOUR=$(staff agent@terrain.gn -X POST "$API/admin/reservations/$RID/release" | jq -r .code)
[ "$FOUR" = ADMIN_ONLY ] && pass "agent cannot release funds" || fail "agent release: $FOUR"
PAYOUT=$(staff admin@terrain.gn -X POST "$API/admin/reservations/$RID/release")
[ "$(jq -r .status <<<"$PAYOUT")" = sent ] && pass "admin released: $(jq -r .amountGnf <<<"$PAYOUT") GNF to seller, fee $(jq -r .feeGnf <<<"$PAYOUT") GNF" || fail "release: $PAYOUT"
sleep 2
[ "$(json "$API/reservations/$RID" -H "authorization: Bearer $BUYER" | jq -r .status)" = released ] && pass "transfer webhook: reservation released" || fail "not released"
[ "$(json "$API/parcels/$ID" -H "authorization: Bearer $SELLER" | jq -r .status)" = sold ] && pass "parcel sold and off the market" || fail "parcel not sold"
echo "Escrow smoke test passed."
