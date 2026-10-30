-- Wallets waiting for an agent to confirm them (releases stay blocked until then).
SELECT id, phone, name, payout_phone, payout_method, payout_verified, parcel_count, created_at
FROM retool.users
WHERE payout_phone IS NOT NULL AND ({{ showVerified.value }} OR NOT payout_verified)
ORDER BY created_at DESC;
