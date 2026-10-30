SELECT created_at, actor, action, data
FROM retool.audit_events
WHERE entity = 'parcel' AND entity_id = {{ parcelTable.selectedRow.id }}
ORDER BY created_at DESC;
