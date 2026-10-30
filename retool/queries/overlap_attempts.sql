-- Fraud page: who tried to submit a boundary that collides with land already on file.
SELECT id, created_at, user_id, phone, attempts_by_user, conflicts, candidate_geojson
FROM retool.overlap_attempts
ORDER BY attempts_by_user DESC, created_at DESC
LIMIT 200;
