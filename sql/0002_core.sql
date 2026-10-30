CREATE TABLE users (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  phone text NOT NULL UNIQUE CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
  name text CHECK (char_length(name) <= 120),
  locale text NOT NULL DEFAULT 'fr' CHECK (locale IN ('fr', 'en')),
  payout_phone text CHECK (payout_phone ~ '^\+224[0-9]{9}$'),
  payout_method text CHECK (payout_method IN ('OM_GN', 'MTN_GN')),
  payout_verified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((payout_phone IS NULL) = (payout_method IS NULL)),
  CHECK (NOT payout_verified OR payout_phone IS NOT NULL)
);

CREATE TABLE refresh_tokens (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  family uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user ON refresh_tokens (user_id);

CREATE TABLE staff (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email text NOT NULL UNIQUE CHECK (email = lower(email)),
  name text NOT NULL,
  role text NOT NULL CHECK (role IN ('agent', 'admin')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Calibration knob: a competing claim is an overlap covering this share of the smaller parcel.
-- Below it (and above the 1 m² noise floor in parcel_conflicts) overlaps are accepted but shown to agents.
CREATE FUNCTION overlap_hard_ratio() RETURNS double precision LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT 0.10::double precision $$;

-- The single definition of an acceptable boundary. The API's dry-run check and the table CHECK both call it.
CREATE FUNCTION parcel_boundary_problem(g geometry) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN GeometryType(g) <> 'POLYGON' OR ST_SRID(g) <> 4326 THEN 'NOT_A_POLYGON'
    WHEN ST_NPoints(g) > 201 THEN 'TOO_MANY_CORNERS'
    WHEN NOT ST_IsValid(g) THEN 'INVALID_GEOMETRY'
    WHEN NOT ST_CoveredBy(g, ST_MakeEnvelope(-15.2, 7.1, -7.5, 12.8, 4326)) THEN 'OUTSIDE_GUINEA'
    WHEN ST_Area(g::geography) NOT BETWEEN 50 AND 5000000 THEN 'AREA_OUT_OF_RANGE'
  END
$$;

CREATE TABLE parcels (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code text GENERATED ALWAYS AS ('TGN-' || lpad(id::text, 6, '0')) STORED UNIQUE,
  owner_id bigint NOT NULL REFERENCES users (id),
  status text NOT NULL DEFAULT 'pending_verification'
    CHECK (status IN ('pending_verification', 'verified', 'reserved', 'sold', 'rejected', 'withdrawn')),
  region text NOT NULL CHECK (region IN ('conakry', 'boke', 'kindia', 'mamou', 'labe', 'faranah', 'kankan', 'nzerekore')),
  prefecture text NOT NULL CHECK (char_length(prefecture) BETWEEN 2 AND 80),
  locality text NOT NULL CHECK (char_length(locality) BETWEEN 2 AND 120),
  title text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 140),
  price_gnf bigint NOT NULL CHECK (price_gnf > 0),
  deposit_gnf bigint CHECK (deposit_gnf > 0 AND deposit_gnf <= price_gnf),
  title_ref text CHECK (char_length(title_ref) BETWEEN 1 AND 80),
  boundary geometry(Polygon, 4326) NOT NULL CONSTRAINT parcels_boundary_ok CHECK (parcel_boundary_problem(boundary) IS NULL),
  area_m2 double precision GENERATED ALWAYS AS (ST_Area(boundary::geography)) STORED,
  verified_by text,
  verified_at timestamptz,
  rejection_reason text,
  idempotency_key text CHECK (char_length(idempotency_key) <= 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- The badge exists exactly when an agent verified the parcel and it has not been unverified or closed.
  CONSTRAINT parcels_badge_consistent CHECK ((status IN ('verified', 'reserved', 'sold')) = (verified_at IS NOT NULL AND verified_by IS NOT NULL))
);
CREATE INDEX parcels_boundary_gist ON parcels USING gist (boundary);
CREATE INDEX parcels_public ON parcels (region, id DESC) WHERE status IN ('verified', 'reserved');
CREATE INDEX parcels_owner ON parcels (owner_id);
CREATE UNIQUE INDEX parcels_idempotency ON parcels (owner_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX parcels_title_ref_active ON parcels (upper(regexp_replace(title_ref, '\s', '', 'g')))
  WHERE title_ref IS NOT NULL AND status NOT IN ('rejected', 'withdrawn');

-- Active parcels whose boundary overlaps `candidate` by more than the noise floor.
-- SECURITY DEFINER so the read-only Retool role can call it through views without base-table grants.
CREATE FUNCTION parcel_conflicts(candidate geometry, exclude_id bigint DEFAULT NULL)
RETURNS TABLE (parcel_id bigint, code text, status text, overlap_m2 double precision, overlap_ratio double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.code, p.status, a.m2, a.m2 / LEAST(p.area_m2, ST_Area(candidate::geography))
  FROM parcels p
  CROSS JOIN LATERAL (SELECT ST_Area(ST_CollectionExtract(ST_Intersection(p.boundary, candidate), 3)::geography) AS m2) a
  WHERE ST_Intersects(p.boundary, candidate)
    AND p.status NOT IN ('rejected', 'withdrawn')
    AND p.id IS DISTINCT FROM exclude_id
    AND a.m2 > 1 -- calibration knob: GPS and floating-point noise floor, in m²
  ORDER BY 5 DESC
$$;

CREATE FUNCTION parcels_guard_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  hits jsonb;
BEGIN
  -- Closed claims never block, and a bad boundary is left for parcels_boundary_ok to reject.
  IF NEW.status IN ('rejected', 'withdrawn') OR parcel_boundary_problem(NEW.boundary) IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- One global lock serializes boundary writes (fine at land-registry volumes); switch to per-geohash-cell locks if submissions ever contend.
  -- Needs READ COMMITTED: the query below takes a fresh snapshot after the lock, so it sees a parcel
  -- committed by the transaction it waited on.
  PERFORM pg_advisory_xact_lock(hashtext('parcels:boundary'));
  SELECT jsonb_agg(jsonb_build_object('code', c.code, 'overlapM2', round(c.overlap_m2::numeric, 1), 'overlapRatio', round(c.overlap_ratio::numeric, 3)))
    INTO hits
    FROM parcel_conflicts(NEW.boundary, NEW.id) c
   WHERE c.overlap_ratio >= overlap_hard_ratio();
  IF hits IS NOT NULL THEN
    RAISE EXCEPTION 'parcel boundary overlaps an existing claim' USING ERRCODE = 'exclusion_violation', DETAIL = hits::text;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER parcels_guard_overlap_insert BEFORE INSERT ON parcels
  FOR EACH ROW EXECUTE FUNCTION parcels_guard_overlap();
CREATE TRIGGER parcels_guard_overlap_update BEFORE UPDATE OF boundary, status ON parcels
  FOR EACH ROW WHEN (OLD.boundary IS DISTINCT FROM NEW.boundary OR OLD.status IN ('rejected', 'withdrawn'))
  EXECUTE FUNCTION parcels_guard_overlap();

CREATE TABLE documents (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parcel_id bigint NOT NULL REFERENCES parcels (id),
  kind text NOT NULL CHECK (kind IN ('title_deed', 'survey_plan', 'photo', 'id_card')),
  s3_key text NOT NULL UNIQUE,
  content_type text NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes integer NOT NULL CHECK (size_bytes BETWEEN 1 AND 10485760),
  uploaded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX documents_parcel ON documents (parcel_id);

CREATE TABLE contact_leads (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parcel_id bigint NOT NULL REFERENCES parcels (id),
  user_id bigint NOT NULL REFERENCES users (id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE overlap_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users (id),
  candidate geometry(Polygon, 4326) NOT NULL,
  conflicts jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor text NOT NULL,
  action text NOT NULL,
  entity text NOT NULL,
  entity_id bigint NOT NULL,
  data jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_entity ON audit_events (entity, entity_id);

CREATE FUNCTION audit_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only';
END
$$;
CREATE TRIGGER audit_events_append_only BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH STATEMENT EXECUTE FUNCTION audit_events_append_only();
