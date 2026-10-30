-- Demo data for screenshots and manual testing: verified parcels around Conakry and the coast.
-- psql "$DATABASE_URL" -f scripts/seed-demo.sql
INSERT INTO staff (email, name, role) VALUES ('agent@terrain.gn', 'Agent Démo', 'agent'), ('admin@terrain.gn', 'Admin Démo', 'admin') ON CONFLICT DO NOTHING;
INSERT INTO users (phone, name) VALUES ('+224620000101', 'Mamadou Bah'), ('+224660000102', 'Fatoumata Camara') ON CONFLICT DO NOTHING;

WITH sellers AS (SELECT id, row_number() OVER (ORDER BY id) AS n FROM users WHERE phone IN ('+224620000101', '+224660000102')),
plots(title, region, prefecture, locality, lon, lat, w, h, price, verified) AS (VALUES
  ('Terrain clôturé avec titre foncier', 'conakry', 'Ratoma', 'Kipé', -13.6512, 9.6371, 20, 25, 450000000, true),
  ('Parcelle viabilisée proche route', 'conakry', 'Ratoma', 'Lambanyi', -13.6203, 9.6672, 25, 30, 380000000, true),
  ('Terrain plat, quartier calme', 'kindia', 'Dubréka', 'Kagbélén', -13.5168, 9.7309, 30, 30, 120000000, true),
  ('Grand terrain agricole', 'kindia', 'Coyah', 'Manéah', -13.4021, 9.7012, 80, 60, 260000000, true),
  ('Terrain en bord de mer', 'boke', 'Boffa', 'Koba', -13.6801, 10.1814, 40, 40, 300000000, true),
  ('Terrain à vérifier', 'conakry', 'Matoto', 'Kissosso', -13.6291, 9.5803, 20, 20, 210000000, false))
INSERT INTO parcels (owner_id, region, prefecture, locality, title, price_gnf, deposit_gnf, boundary, status, verified_by, verified_at)
SELECT s.id, p.region, p.prefecture, p.locality, p.title, p.price, 1000000,
       ST_SetSRID(ST_MakeEnvelope(p.lon, p.lat, p.lon + p.w / 109790.0, p.lat + p.h / 110610.0), 4326),
       CASE WHEN p.verified THEN 'verified' ELSE 'pending_verification' END,
       CASE WHEN p.verified THEN 'agent@terrain.gn' END,
       CASE WHEN p.verified THEN now() - interval '2 days' END
FROM plots p JOIN sellers s ON s.n = 1 + (length(p.locality) % 2);
