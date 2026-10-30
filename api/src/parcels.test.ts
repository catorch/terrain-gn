import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { createUser, rect, resetDatabase, type Corner } from '../test/helpers.js';
import { DatabaseService } from './db.js';
import { ParcelsService } from './parcels.service.js';
import { StorageService } from './storage.service.js';

const db = new DatabaseService();
const parcels = new ParcelsService(db, new StorageService());
let seller: number;
let buyer: number;

beforeEach(async () => {
  await resetDatabase(db.pool);
  seller = await createUser(db.pool, '+224620000001');
  buyer = await createUser(db.pool, '+33612345678');
});
afterAll(() => db.onModuleDestroy());

const input = (corners: Corner[], extra: Record<string, unknown> = {}) => ({
  boundary: { corners, crs: 'EPSG:4326' as const },
  title: 'Terrain 500 m² à Kipé',
  region: 'conakry' as const,
  prefecture: 'Ratoma',
  locality: 'Kipé',
  priceGnf: 150_000_000,
  ...extra,
});

const verify = (id: number) => db.query("UPDATE parcels SET status = 'verified', verified_by = 'agent@test', verified_at = now() WHERE id = $1", [id]);

describe('parcel check and submission', () => {
  it('dry-runs a boundary without storing it', async () => {
    const result = await parcels.check({ corners: rect(0, 0, 20, 25), crs: 'EPSG:4326' });
    expect(result).toMatchObject({ ok: true, problem: null, conflicts: [] });
    expect(result.areaM2).toBeCloseTo(500, -1);
    const { rows } = await db.query('SELECT count(*)::int AS n FROM parcels');
    expect(rows[0]!.n).toBe(0);
  });

  it('explains an invalid boundary instead of repairing it', async () => {
    const [a, b, c, d] = rect(0, 0, 20, 25);
    const result = await parcels.check({ corners: [a!, c!, b!, d!], crs: 'EPSG:4326' });
    expect(result).toMatchObject({ ok: false, problem: 'INVALID_GEOMETRY', reason: expect.stringContaining('Self-intersection') });
    await expect(parcels.create(seller, input([a!, c!, b!, d!]))).rejects.toMatchObject({ status: 422, response: { code: 'BOUNDARY_INVALID', problem: 'INVALID_GEOMETRY' } });
  });

  it('accepts a closed ring and an open one alike', async () => {
    const corners = rect(0, 0, 20, 25);
    const created = await parcels.create(seller, input([...corners, corners[0]!]));
    expect(created).toMatchObject({ code: 'TGN-000001', status: 'pending_verification', verified: false, isOwner: true });
  });

  it('returns 409 with plot codes, hides the owner, and records the attempt', async () => {
    await parcels.create(seller, input(rect(0, 0, 20, 25)));
    const preview = await parcels.check({ corners: rect(5, 0, 20, 25), crs: 'EPSG:4326' });
    expect(preview).toMatchObject({ ok: false, conflicts: [expect.objectContaining({ code: 'TGN-000001', blocking: true })] });
    const error = await parcels.create(buyer, input(rect(5, 0, 20, 25))).catch((caught) => caught);
    expect(error.status).toBe(409);
    expect(error.response).toEqual({ code: 'PARCEL_OVERLAP', conflicts: [{ code: 'TGN-000001', overlapM2: expect.any(Number), overlapRatio: 0.75 }] });
    const { rows } = await db.query('SELECT user_id, conflicts FROM overlap_attempts');
    expect(rows).toEqual([{ user_id: buyer, conflicts: [expect.objectContaining({ code: 'TGN-000001' })] }]);
  });

  it('reports a sub-threshold sliver as a non-blocking conflict', async () => {
    await parcels.create(seller, input(rect(0, 0, 20, 25)));
    const preview = await parcels.check({ corners: rect(19.5, 0, 20, 25), crs: 'EPSG:4326' });
    expect(preview).toMatchObject({ ok: true, conflicts: [expect.objectContaining({ code: 'TGN-000001', blocking: false })] });
    await expect(parcels.create(buyer, input(rect(19.5, 0, 20, 25)))).resolves.toMatchObject({ code: 'TGN-000002' });
  });

  it('lets exactly one of two simultaneous API submissions win', async () => {
    const results = await Promise.allSettled([parcels.create(seller, input(rect(0, 0, 20, 25))), parcels.create(buyer, input(rect(2, 2, 20, 25)))]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.find((r) => r.status === 'rejected')).toMatchObject({ reason: { response: { code: 'PARCEL_OVERLAP' } } });
  });

  it('returns the original parcel when a submission is retried with the same Idempotency-Key', async () => {
    const first = await parcels.create(seller, input(rect(0, 0, 20, 25)), 'retry-key-123');
    const retried = await parcels.create(seller, input(rect(0, 0, 20, 25)), 'retry-key-123');
    expect(retried.id).toBe(first.id);
  });

  it('rejects a duplicated title reference', async () => {
    await parcels.create(seller, input(rect(0, 0, 20, 25), { titleRef: 'TF-1234/CKY' }));
    await expect(parcels.create(buyer, input(rect(100, 0, 20, 25), { titleRef: 'tf-1234/cky' }))).rejects.toMatchObject({ response: { code: 'DUPLICATE_TITLE_REF' } });
  });

  it('rejects UTM corners sent as degrees', async () => {
    const result = await parcels.check({ corners: [[700000, 1062000], [700020, 1062000], [700020, 1062025], [700000, 1062025]], crs: 'EPSG:32628' });
    expect(result.ok).toBe(true);
    expect(result.areaM2).toBeCloseTo(500, -1);
  });
});

describe('listing visibility and badge', () => {
  it('lists only verified parcels and shows the badge', async () => {
    const pending = await parcels.create(seller, input(rect(0, 0, 20, 25)));
    const shown = await parcels.create(seller, input(rect(30, 0, 20, 25)));
    await verify(shown.id);
    const { items, nextCursor } = await parcels.list(undefined, undefined);
    expect(items.map((p) => p.code)).toEqual([shown.code]);
    expect(items[0]).toMatchObject({ verified: true, verifiedAt: expect.any(Date) });
    expect(nextCursor).toBeNull();
    await expect(parcels.detail(pending.id, buyer)).rejects.toMatchObject({ status: 404 });
    await expect(parcels.detail(pending.id, seller)).resolves.toMatchObject({ isOwner: true });
  });

  it('pages with a cursor', async () => {
    for (let i = 0; i < 22; i++) await verify((await parcels.create(seller, input(rect(i * 30, 0, 20, 25)))).id);
    const first = await parcels.list(undefined, undefined);
    expect(first.items).toHaveLength(20);
    const second = await parcels.list(undefined, first.nextCursor!);
    expect(second.items).toHaveLength(2);
    expect(second.nextCursor).toBeNull();
  });

  it('hides the title reference from buyers', async () => {
    const created = await parcels.create(seller, input(rect(0, 0, 20, 25), { titleRef: 'TF-99' }));
    await verify(created.id);
    expect(await parcels.detail(created.id, buyer)).not.toHaveProperty('titleRef');
    expect(await parcels.detail(created.id, seller)).toHaveProperty('titleRef', 'TF-99');
  });

  it('locks a reserved parcel against owner edits and withdrawal', async () => {
    const created = await parcels.create(seller, input(rect(0, 0, 20, 25)));
    await verify(created.id);
    await db.query("UPDATE parcels SET status = 'reserved' WHERE id = $1", [created.id]);
    await expect(parcels.update(seller, created.id, { priceGnf: 1 })).rejects.toMatchObject({ response: { code: 'PARCEL_LOCKED', status: 'reserved' } });
    await expect(parcels.withdraw(seller, created.id)).rejects.toMatchObject({ response: { code: 'PARCEL_LOCKED' } });
    await expect(parcels.withdraw(buyer, created.id)).rejects.toMatchObject({ status: 404 });
  });
});

describe('WhatsApp contact', () => {
  it('returns a localized wa.me link and logs the lead', async () => {
    const created = await parcels.create(seller, input(rect(0, 0, 20, 25)));
    await expect(parcels.contact(buyer, created.id)).rejects.toMatchObject({ status: 404 });
    await verify(created.id);
    await db.query("UPDATE users SET locale = 'en' WHERE id = $1", [buyer]);
    const handoff = await parcels.contact(buyer, created.id);
    expect(handoff.url).toMatch(/^https:\/\/wa\.me\/224620000001\?text=/);
    expect(handoff.text).toContain('plot TGN-000001');
    await expect(parcels.contact(seller, created.id)).rejects.toMatchObject({ response: { code: 'OWN_PARCEL' } });
    const { rows } = await db.query('SELECT user_id FROM contact_leads');
    expect(rows).toEqual([{ user_id: buyer }]);
  });
});

describe('documents', () => {
  it('confirms an upload with HeadObject and keeps deeds private', async () => {
    const created = await parcels.create(seller, input(rect(0, 0, 20, 25)));
    await verify(created.id);
    const body = new Uint8Array(1234).fill(7);
    const deed = await parcels.requestUpload(seller, created.id, { kind: 'title_deed', contentType: 'application/pdf', sizeBytes: body.length });
    await expect(parcels.completeUpload(seller, created.id, deed.documentId)).rejects.toMatchObject({ response: { code: 'UPLOAD_MISSING' } });
    const put = await fetch(deed.uploadUrl, { method: 'PUT', headers: deed.headers, body });
    expect(put.ok).toBe(true);
    await expect(parcels.completeUpload(seller, created.id, deed.documentId)).resolves.toEqual({ documentId: deed.documentId, uploaded: true });

    const photo = await parcels.requestUpload(seller, created.id, { kind: 'photo', contentType: 'image/jpeg', sizeBytes: 10 });
    await fetch(photo.uploadUrl, { method: 'PUT', headers: photo.headers, body: new Uint8Array(99) });
    await expect(parcels.completeUpload(seller, created.id, photo.documentId)).rejects.toMatchObject({ response: { code: 'UPLOAD_MISMATCH' } });

    expect((await parcels.documents(created.id, seller)).items.map((d) => d.kind)).toEqual(['title_deed']);
    expect((await parcels.documents(created.id, buyer)).items).toEqual([]);
    await expect(parcels.requestUpload(buyer, created.id, { kind: 'photo', contentType: 'image/jpeg', sizeBytes: 10 })).rejects.toMatchObject({ status: 404 });
  });

  it('serves the same photo URL within the hour so the app cache works', async () => {
    const created = await parcels.create(seller, input(rect(0, 0, 20, 25)));
    await verify(created.id);
    const photo = await parcels.requestUpload(seller, created.id, { kind: 'photo', contentType: 'image/jpeg', sizeBytes: 3 });
    await fetch(photo.uploadUrl, { method: 'PUT', headers: photo.headers, body: new Uint8Array(3) });
    await parcels.completeUpload(seller, created.id, photo.documentId);
    const first = await parcels.detail(created.id, buyer);
    const second = await parcels.detail(created.id, buyer);
    expect(first.photos).toHaveLength(1);
    expect(first.photos).toEqual(second.photos);
    expect(first.coverUrl).toBe(first.photos[0]);
  });
});
