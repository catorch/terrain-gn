# Terrain GN

Land reservation for the Guinean diaspora, built to make property fraud hard:

- **One plot, one claim.** PostGIS rejects any boundary that overlaps land already on file. The rule lives in the database, so no API bug or Retool query can get around it.
- **Verified on the ground.** A field agent toggles a badge in Retool after visiting the plot. Only verified plots are listed.
- **WhatsApp handoff.** Buyers reach the seller through a pre-filled `wa.me` link built by the server.
- **Escrow deposits (Phase 2).** CinetPay collects the deposit. It is paid out to the seller's Orange Money or MTN wallet only when an admin releases it, and never by the agent who verified the plot.

## Screenshots

Taken from the running app (web build, phone size) against the local API with demo data. The plot photos are AI-generated placeholders.

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/listings-fr.png" width="230"><br><sub>Verified listings (FR)</sub></td>
    <td align="center"><img src="docs/screenshots/detail-fr.png" width="230"><br><sub>Plot detail, badge, boundary markers</sub></td>
    <td align="center"><img src="docs/screenshots/whatsapp-fr.png" width="230"><br><sub>WhatsApp handoff sheet</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/overlap-rejected-fr.png" width="230"><br><sub>Overlapping boundary rejected</sub></td>
    <td align="center"><img src="docs/screenshots/reserve-fr.png" width="230"><br><sub>Escrow deposit secured</sub></td>
    <td align="center"><img src="docs/screenshots/listings-en.png" width="230"><br><sub>English interface</sub></td>
  </tr>
</table>

<details><summary>Phone sign-in (SMS or WhatsApp code)</summary><br><img src="docs/screenshots/login-fr.png" width="230"></details>

Retool admin build guide: [retool/README.md](retool/README.md)

```
api/      NestJS + pg + zod (TypeScript). One module, plain SQL.
sql/      Ordered, checksummed migrations. The spatial engine is in 0002_core.sql.
mobile/   Flutter app in EN and FR (Android, iOS, web).
retool/   Admin build guide and SQL queries.
scripts/  smoke.sh, smoke-escrow.sh, seed-demo.sql, fake-cinetpay.mjs
```

## Run locally

Requirements: Node 24, pnpm 10, Docker, and Flutter 3.47.

```bash
cp .env.example .env
docker compose up -d db s3                      # PostGIS 17 and an S3 mock
cd api && pnpm install && pnpm migrate && pnpm dev   # API on :4100. The OTP code is 000000 outside production.
psql postgresql://terrain:terrain@localhost:5435/terrain -f ../scripts/seed-demo.sql   # demo plots, plus an agent and an admin
```

Run the app:

```bash
cd mobile
flutter run -d chrome --dart-define=API_URL=http://localhost:4100/v1
flutter run                                     # Android emulator; the default API URL is http://10.0.2.2:4100/v1
flutter build appbundle --dart-define=API_URL=https://<api-host>/v1   # Play Store builds per device, about 17–20 MB
```

For the escrow flow without CinetPay keys, run the local fake gateway:

```bash
node scripts/fake-cinetpay.mjs &                # http://localhost:9300
CINETPAY_BASE_URL=http://localhost:9300 CINETPAY_API_KEY=fake CINETPAY_API_PASSWORD=fake pnpm -C api dev
```

## Tests

```bash
pnpm -C api test        # Uses a real PostGIS. It recreates terrain_test from the migrations on every run.
pnpm -C api typecheck
(cd mobile && flutter analyze && flutter test)
ADMIN_API_KEY=change-me-admin-key-for-retool scripts/smoke.sh          # Phase 1 over HTTP
ADMIN_API_KEY=change-me-admin-key-for-retool scripts/smoke-escrow.sh   # Phase 2 over HTTP, against the fake gateway
```

The API suite has 60 tests. They cover:
- **The overlap engine:** containment in both directions, slivers below the 10% threshold, edges that only touch, bow-tie polygons, boundaries outside Guinea, UTM 28N input, duplicate title numbers, and a two-connection race where exactly one submission must win.
- **Auth:** refresh rotation with reuse revocation.
- **S3 uploads:** presigned PUT, then a `HeadObject` size check.
- **The Retool read-only role.**
- **The escrow state machine:** a forged webhook, duplicate webhooks, the status API overriding the webhook, an amount mismatch, a late payment, the four-eyes release rule, unverified wallets, and crash recovery that never pays twice.

## Deploy

```bash
docker build -f api/Dockerfile -t terrain-gn-api .
```

The container runs migrations, then starts the API. With `NODE_ENV=production` it refuses to boot without Twilio Verify and S3 credentials. Escrow endpoints return `503 PAYMENTS_NOT_CONFIGURED` until the CinetPay keys are set, so Phase 1 can launch on its own.

Environment variables are listed in [.env.example](.env.example). Put TLS and a reverse proxy in front. `trust proxy` is set to 1 hop, so the OTP rate limit sees the real client IP.

## Open questions

1. **CinetPay account details.** Which API generation is the account on: the v1 JWT API (what `api/src/cinetpay.ts` targets) or the classic apikey/site_id checkout? Are GNF collections and transfers enabled for Guinea, and what are the real per-transaction limits? The default cap is 1.5M GNF, which is about US$170, so this is a deposit and not the full price.
2. **Diaspora card payments.** CinetPay is mobile money only, so diaspora buyers paying by EUR or USD card would need a second gateway, such as Flutterwave.
3. **Legal review.** Deposits sit in the platform's CinetPay merchant balance. That needs a legal check against the claim that "we don't hold deposits".
4. **WhatsApp target.** Should buyers reach the seller directly (the current behaviour) or an ops number?
5. **Refunds.** A buyer without a Guinean wallet cannot be refunded through the payout API.
6. **Overlap threshold.** The 10% rule (`overlap_hard_ratio()`) and the 1 m² noise floor need calibrating against real survey data.
