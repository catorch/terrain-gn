SELECT id, created_at, parcel_id, code, locality, buyer_phone, seller_phone
FROM retool.contact_leads
WHERE ({{ !parcelTable.selectedRow }} OR parcel_id = {{ parcelTable.selectedRow?.id }})
ORDER BY created_at DESC
LIMIT 200;
