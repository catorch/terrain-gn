SELECT id, merchant_tx_id, status, review_reason, amount_gnf, created_at, paid_at, expires_at,
       parcel_id, code, parcel_status, verified_by,
       buyer_phone, buyer_wallet, buyer_wallet_verified,
       seller_id, seller_phone, seller_wallet, seller_method, seller_wallet_verified, payouts
FROM retool.reservations
WHERE ({{ showClosed.value }} OR status IN ('pending_payment', 'held', 'needs_review'))
ORDER BY (status = 'needs_review') DESC, (status = 'held') DESC, created_at DESC
LIMIT 200;
