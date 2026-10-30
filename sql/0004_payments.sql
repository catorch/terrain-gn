-- Escrow (Phase 2). Money states live here; CinetPay holds the funds and is asked for the truth on every change.
CREATE TABLE reservations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  merchant_tx_id text GENERATED ALWAYS AS ('TGN-R-' || id) STORED UNIQUE, -- CinetPay limit: 30 characters
  parcel_id bigint NOT NULL REFERENCES parcels (id),
  buyer_id bigint NOT NULL REFERENCES users (id),
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  status text NOT NULL DEFAULT 'pending_payment'
    CHECK (status IN ('pending_payment', 'held', 'released', 'refunded', 'failed', 'expired', 'needs_review')),
  review_reason text,
  idempotency_key text NOT NULL CHECK (char_length(idempotency_key) BETWEEN 8 AND 100),
  provider_tx_id text,
  notify_token text,
  payment_url text,
  expires_at timestamptz NOT NULL,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (buyer_id, idempotency_key)
);
CREATE UNIQUE INDEX reservations_one_active ON reservations (parcel_id) WHERE status IN ('pending_payment', 'held');
CREATE INDEX reservations_buyer ON reservations (buyer_id);

CREATE TABLE payouts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  merchant_tx_id text GENERATED ALWAYS AS ('TGN-P-' || id) STORED UNIQUE,
  reservation_id bigint NOT NULL REFERENCES reservations (id),
  kind text NOT NULL CHECK (kind IN ('release', 'refund')),
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0), -- what the recipient receives
  fee_gnf bigint NOT NULL DEFAULT 0 CHECK (fee_gnf >= 0),
  phone text NOT NULL CHECK (phone ~ '^\+224[0-9]{9}$'),
  method text NOT NULL CHECK (method IN ('OM_GN', 'MTN_GN')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'succeeded', 'failed')),
  provider_tx_id text,
  notify_token text,
  failure_reason text,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
-- A failed payout can be retried with a new row; two live payouts for one deposit cannot exist.
CREATE UNIQUE INDEX payouts_one_active ON payouts (reservation_id) WHERE status IN ('pending', 'sent', 'succeeded');

CREATE TABLE payment_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider_tx_id text NOT NULL,
  status text NOT NULL,
  reservation_id bigint REFERENCES reservations (id),
  payout_id bigint REFERENCES payouts (id),
  raw jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider_tx_id, status)
);

CREATE VIEW retool.reservations AS
SELECT r.id, r.merchant_tx_id, r.status, r.review_reason, r.amount_gnf, r.created_at, r.paid_at, r.expires_at,
       p.id AS parcel_id, p.code, p.status AS parcel_status, p.verified_by,
       buyer.phone AS buyer_phone, buyer.payout_phone AS buyer_wallet, buyer.payout_verified AS buyer_wallet_verified,
       seller.id AS seller_id, seller.phone AS seller_phone, seller.payout_phone AS seller_wallet, seller.payout_method AS seller_method,
       seller.payout_verified AS seller_wallet_verified,
       (SELECT json_agg(json_build_object('id', o.id, 'kind', o.kind, 'status', o.status, 'amount', o.amount_gnf, 'fee', o.fee_gnf,
                'failure', o.failure_reason, 'createdBy', o.created_by) ORDER BY o.id)
          FROM payouts o WHERE o.reservation_id = r.id) AS payouts
FROM reservations r
JOIN parcels p ON p.id = r.parcel_id
JOIN users buyer ON buyer.id = r.buyer_id
JOIN users seller ON seller.id = p.owner_id;

CREATE VIEW retool.payouts AS
SELECT o.id, o.merchant_tx_id, o.reservation_id, o.kind, o.status, o.amount_gnf, o.fee_gnf, o.phone, o.method,
       o.failure_reason, o.created_by, o.created_at, o.updated_at
FROM payouts o;

GRANT SELECT ON retool.reservations, retool.payouts TO retool_ro;
