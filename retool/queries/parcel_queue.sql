-- Resource: terrain_ro (Postgres, user retool_ro). Run on page load and after every action.
SELECT id, code, status, title, region, prefecture, locality, price_gnf, area_m2, title_ref,
       owner_id, owner_phone, owner_name, verified_by, verified_at, created_at,
       lat, lon, boundary_geojson, soft_overlaps, document_count, lead_count
FROM retool.parcel_queue
WHERE ({{ !statusFilter.value }} OR status = {{ statusFilter.value }})
  AND ({{ !search.value }} OR code ILIKE {{ '%' + search.value + '%' }} OR locality ILIKE {{ '%' + search.value + '%' }} OR owner_phone ILIKE {{ '%' + search.value + '%' }})
ORDER BY (status = 'pending_verification') DESC, created_at
LIMIT 200;
