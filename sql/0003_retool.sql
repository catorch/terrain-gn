-- Read-only surface for Retool. Retool reads these views as retool_ro and writes only through the admin API,
-- so every state change goes through the same validation and audit trail as the app.
CREATE SCHEMA retool;

CREATE VIEW retool.parcel_queue AS
SELECT p.id, p.code, p.status, p.title, p.region, p.prefecture, p.locality, p.price_gnf, p.deposit_gnf,
       round(p.area_m2) AS area_m2, p.title_ref, p.owner_id, u.phone AS owner_phone, u.name AS owner_name,
       p.verified_by, p.verified_at, p.rejection_reason, p.created_at,
       ST_Y(ST_Centroid(p.boundary)) AS lat, ST_X(ST_Centroid(p.boundary)) AS lon,
       ST_AsGeoJSON(p.boundary, 7)::json AS boundary_geojson,
       (SELECT coalesce(json_agg(json_build_object('code', c.code, 'status', c.status, 'overlapM2', round(c.overlap_m2::numeric, 1),
                'overlapRatio', round(c.overlap_ratio::numeric, 3))), '[]')
          FROM parcel_conflicts(p.boundary, p.id) c) AS soft_overlaps,
       (SELECT count(*) FROM documents d WHERE d.parcel_id = p.id AND d.uploaded_at IS NOT NULL) AS document_count,
       (SELECT count(*) FROM contact_leads l WHERE l.parcel_id = p.id) AS lead_count
FROM parcels p
JOIN users u ON u.id = p.owner_id;

CREATE VIEW retool.overlap_attempts AS
SELECT a.id, a.created_at, a.user_id, u.phone, a.conflicts,
       ST_AsGeoJSON(a.candidate, 7)::json AS candidate_geojson,
       (SELECT count(*) FROM overlap_attempts o WHERE o.user_id = a.user_id) AS attempts_by_user
FROM overlap_attempts a
JOIN users u ON u.id = a.user_id;

CREATE VIEW retool.contact_leads AS
SELECT l.id, l.created_at, p.id AS parcel_id, p.code, p.locality, buyer.phone AS buyer_phone, seller.phone AS seller_phone
FROM contact_leads l
JOIN parcels p ON p.id = l.parcel_id
JOIN users buyer ON buyer.id = l.user_id
JOIN users seller ON seller.id = p.owner_id;

CREATE VIEW retool.users AS
SELECT u.id, u.phone, u.name, u.locale, u.payout_phone, u.payout_method, u.payout_verified, u.created_at,
       (SELECT count(*) FROM parcels p WHERE p.owner_id = u.id) AS parcel_count
FROM users u;

CREATE VIEW retool.audit_events AS
SELECT id, created_at, actor, action, entity, entity_id, data FROM audit_events;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'retool_ro') THEN
    CREATE ROLE retool_ro NOLOGIN; -- ops: ALTER ROLE retool_ro LOGIN PASSWORD '...';
  END IF;
END
$$;
GRANT USAGE ON SCHEMA retool TO retool_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA retool TO retool_ro;
