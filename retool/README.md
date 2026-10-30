# Retool admin

Retool has two jobs here: field agents use it to verify parcels (which turns the badge on in the app), and ops use it to review fraud signals. All reads go to SQL views as a read-only role, and all writes go through the admin API. That way a button in Retool runs the same validation and writes the same audit row as everything else, and nobody can bypass the overlap engine with an `UPDATE`.

The app itself has to be assembled in a Retool workspace. This file covers everything needed to do that in about an hour.

## 1. Resources

**terrain_ro (PostgreSQL)**: read-only.

```sql
-- once, as the database owner (migration 0003 creates the role as NOLOGIN)
ALTER ROLE retool_ro LOGIN PASSWORD '<generate>';
```

Host, port and database are the production Postgres. The user is `retool_ro`, and SSL is required. This role can `SELECT` from the `retool.*` views only. It has no access to the base tables.

**terrain_api (REST API)**: writes.

| Setting | Value |
| --- | --- |
| Base URL | `https://<api-host>/v1/admin` |
| Header `Authorization` | `Bearer <ADMIN_API_KEY>` (store it as a Retool secret) |
| Header `x-actor-email` | `{{ current_user.email }}` |
| Header `content-type` | `application/json` |

The API maps `x-actor-email` to an active row in `staff`. A Retool user without a staff row gets `403 STAFF_UNKNOWN`, so add every agent first:

```sql
INSERT INTO staff (email, name, role) VALUES ('aissatou@terrain.gn', 'Aïssatou Diallo', 'agent');
-- role 'admin' is needed for escrow release and refund (Phase 2). Deactivate with: UPDATE staff SET active = false ...
```

In Retool, create two permission groups, **Field agents** and **Admins**. Give Field agents access to the Verification and Fraud pages only. The API enforces the same roles on its side.

## 2. Page: Verification queue

| Component | Setup |
| --- | --- |
| `statusFilter` (Select) | Options `pending_verification`, `verified`, `reserved`, `sold`, `rejected`, `withdrawn`. Default `pending_verification`. |
| `search` (Text input) | Filters by plot code, locality, or owner phone. |
| `parcelQueue` (SQL query, terrain_ro) | [`queries/parcel_queue.sql`](queries/parcel_queue.sql). Run on page load and whenever the inputs change. |
| `parcelTable` (Table) | Data `{{ parcelQueue.data }}`. Columns: code, status, locality, prefecture, area_m2, price_gnf, owner_phone, document_count, lead_count, created_at. Add a tag column for `soft_overlaps.length > 0`, labelled "Overlap ≤10%", so agents see slivers before they go into the field. |
| `parcelMap` (Map) | Latitude `{{ parcelTable.selectedRow.lat }}`, longitude `{{ parcelTable.selectedRow.lon }}`, zoom 18. GeoJSON `{{ { type: 'Feature', geometry: parcelTable.selectedRow.boundary_geojson } }}`. Use the satellite style so the agent can compare the boundary with the walls on the ground. |
| `softOverlaps` (Table) | Data `{{ parcelTable.selectedRow.soft_overlaps }}`. Shows which neighbouring plot codes overlap and by how many m². |
| `documents` (REST query, terrain_api) | `GET /parcels/{{ parcelTable.selectedRow.id }}/documents`. Run when the selected row changes. |
| `documentList` (List view or Table) | `{{ documents.data.items }}`. A link column opens `url` (presigned, valid for 1–2 h). Deeds and ID cards are only visible here and to the owner. |
| `history` (SQL query) | [`queries/parcel_history.sql`](queries/parcel_history.sql), shown in a small table. |
| `note` (Text area) | The agent's field note. It is stored in the audit event. |

Buttons. Each one is a REST query on **terrain_api**, and on success triggers `parcelQueue`:

| Button | Query | Show when |
| --- | --- | --- |
| **Verify ✓** (primary) | `POST /parcels/{{ parcelTable.selectedRow.id }}/verification` with body `{ "verified": true, "note": {{ note.value }} }` | `status === 'pending_verification'` |
| **Remove badge** | the same endpoint with `{ "verified": false, "note": {{ note.value }} }` | `status === 'verified'` |
| **Reject** | `POST /parcels/{{ parcelTable.selectedRow.id }}/reject` with body `{ "reason": {{ note.value }} }`. Add a confirmation modal. | `status` is `pending_verification` or `verified` |

Verify and Remove badge are the "badge toggle". The app shows the badge on its next fetch of the parcel (pull-to-refresh or opening the detail screen). Listings only include verified parcels, so removing the badge also takes the listing down. The API refuses to remove the badge from a reserved or sold parcel (`409 INVALID_STATUS`), because money is attached to it.

Show API errors with an event handler: `utils.showNotification({ title: 'Refused', description: verifyParcel.error, notificationType: 'error' })`. The response `code` explains why, for example `INVALID_STATUS`.

## 3. Page: Fraud

| Component | Setup |
| --- | --- |
| `overlapAttempts` | [`queries/overlap_attempts.sql`](queries/overlap_attempts.sql) in a table. The rows at the top are the users who have tried most often. |
| `attemptMap` (Map) | GeoJSON `{{ { type: 'Feature', geometry: attemptsTable.selectedRow.candidate_geojson } }}`. Shows the boundary that was refused. `conflicts` lists the plot codes it collided with, so look those up in the queue. |
| `leads` | [`queries/contact_leads.sql`](queries/contact_leads.sql). Every "Contacter via WhatsApp" tap, with the buyer and seller phones, for following up deals that happen on WhatsApp. |

## 4. Page: Payout wallets

| Component | Setup |
| --- | --- |
| `showVerified` (Switch) | Off by default. |
| `wallets` | [`queries/payout_wallets.sql`](queries/payout_wallets.sql) in a table. |
| **Confirm wallet** | `POST /users/{{ walletsTable.selectedRow.id }}/payout-verification` with body `{ "verified": true, "payoutPhone": {{ walletsTable.selectedRow.payout_phone }} }` |

The body repeats the wallet number the agent is looking at. If the user changed it in the meantime, the API answers `409 PAYOUT_WALLET_CHANGED` instead of approving a number nobody checked.

## 5. Page: Escrow (Admins only)

| Component | Setup |
| --- | --- |
| `reservations` | [`queries/reservations.sql`](queries/reservations.sql) in a table. Color the status column: `held` green, `needs_review` amber, `failed`/`expired` grey. |
| `payoutsTable` | `{{ reservationsTable.selectedRow.payouts }}` |
| **Release to seller** | `POST /reservations/{{ reservationsTable.selectedRow.id }}/release`. Shown when `status === 'held'`. Add a confirmation modal that shows `seller_wallet`, the amount and the fee. |
| **Refund buyer** | `POST /reservations/{{ reservationsTable.selectedRow.id }}/refund`. Shown when `status` is `held`, or `needs_review` with `paid_at` set. |
| **Reconcile** | `POST /payouts/{{ payoutsTable.selectedRow.id }}/reconcile`. Shown when the payout is `pending` or `sent`. |

Rules the API enforces. Each refusal comes back as a `code` to show in the error notification:

- `FOUR_EYES_REQUIRED`: the admin releasing the funds verified this parcel. Another admin must release.
- `PAYOUT_WALLET_UNVERIFIED`: confirm the recipient's wallet on the Payout wallets page first. Changing a wallet always un-confirms it.
- `PAYOUT_EXISTS`: a payout for this deposit is already pending, sent or paid. A failed payout can be retried.
- `INVALID_STATUS`: the deposit is not in a state that can be released or refunded.

**`needs_review` reasons:**
- `AMOUNT_MISMATCH`: CinetPay reported a different amount or currency from the deposit.
- `PARCEL_UNAVAILABLE`: the payment arrived after the reservation expired, and someone else holds the plot, or the plot was withdrawn.

Both are paid deposits with no plot attached, so refund them.

**Reconcile** is for a payout stuck in `pending`. That happens when the API went down between saving the payout and calling CinetPay. Reconcile asks CinetPay whether the transfer exists and re-sends it only if it doesn't, under the same merchant id, so the payment can never go out twice.
