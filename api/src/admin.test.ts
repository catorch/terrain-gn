import type { ExecutionContext } from '@nestjs/common';
import pg from 'pg';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { createUser, rect, resetDatabase } from '../test/helpers.js';
import { AdminController, AdminGuard, type Staff } from './admin.controller.js';
import { DatabaseService } from './db.js';
import { ParcelsService } from './parcels.service.js';
import { StorageService } from './storage.service.js';

const db = new DatabaseService();
const storage = new StorageService();
const parcels = new ParcelsService(db, storage);
const admin = new AdminController(db, storage);
const guard = new AdminGuard(db);
const agent = { staff: { email: 'agent@terrain.gn', role: 'agent' } as Staff } as never;
let seller: number;
let parcelId: number;

beforeEach(async () => {
  await resetDatabase(db.pool);
  await db.query("INSERT INTO staff (email, name, role) VALUES ('agent@terrain.gn', 'Agent', 'agent'), ('old@terrain.gn', 'Old', 'agent')");
  await db.query("UPDATE staff SET active = false WHERE email = 'old@terrain.gn'");
  seller = await createUser(db.pool, '+224620000001');
  const created = await parcels.create(seller, {
    boundary: { corners: rect(0, 0, 20, 25), crs: 'EPSG:4326' },
    title: 'Terrain',
    region: 'conakry',
    prefecture: 'Ratoma',
    locality: 'Kipé',
    priceGnf: 1_000_000,
  });
  parcelId = created.id;
});
afterAll(() => db.onModuleDestroy());

function context(headers: Record<string, string>) {
  const request = { headers } as { headers: Record<string, string>; staff?: Staff };
  return { request, ctx: { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext };
}

describe('admin guard', () => {
  it('needs the shared key and an active staff email', async () => {
    const key = `Bearer ${process.env.ADMIN_API_KEY}`;
    await expect(guard.canActivate(context({ authorization: 'Bearer wrong', 'x-actor-email': 'agent@terrain.gn' }).ctx)).rejects.toMatchObject({ status: 401 });
    await expect(guard.canActivate(context({ authorization: key, 'x-actor-email': 'old@terrain.gn' }).ctx)).rejects.toMatchObject({ status: 403 });
    const { request, ctx } = context({ authorization: key, 'x-actor-email': ' Agent@Terrain.GN ' });
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(request.staff).toEqual({ email: 'agent@terrain.gn', role: 'agent' });
  });
});

describe('verification badge toggle', () => {
  it('verifies, shows the badge on the next read, and unverifies', async () => {
    await expect(admin.setVerification(agent, parcelId, { verified: true, note: 'Bornes vues sur le terrain' })).resolves.toEqual({ id: parcelId, status: 'verified', verified: true });
    expect(await parcels.detail(parcelId)).toMatchObject({ verified: true, status: 'verified' });
    expect((await parcels.list(undefined, undefined)).items).toHaveLength(1);
    await admin.setVerification(agent, parcelId, { verified: false });
    expect((await parcels.list(undefined, undefined)).items).toHaveLength(0);
    const { rows } = await db.query('SELECT actor, action, data FROM audit_events WHERE entity = $1 ORDER BY id', ['parcel']);
    expect(rows.slice(1)).toEqual([
      { actor: 'staff:agent@terrain.gn', action: 'parcel.verified', data: { note: 'Bornes vues sur le terrain' } },
      { actor: 'staff:agent@terrain.gn', action: 'parcel.unverified', data: {} },
    ]);
  });

  it('does not unverify a reserved parcel or verify a rejected one', async () => {
    await admin.setVerification(agent, parcelId, { verified: true });
    await db.query("UPDATE parcels SET status = 'reserved' WHERE id = $1", [parcelId]);
    await expect(admin.setVerification(agent, parcelId, { verified: false })).rejects.toMatchObject({ response: { code: 'INVALID_STATUS', status: 'reserved' } });
    await db.query("UPDATE parcels SET status = 'pending_verification', verified_at = NULL, verified_by = NULL WHERE id = $1", [parcelId]);
    await admin.reject(agent, parcelId, { reason: 'Titre falsifié' });
    await expect(admin.setVerification(agent, parcelId, { verified: true })).rejects.toMatchObject({ response: { code: 'INVALID_STATUS', status: 'rejected' } });
  });

  it('only approves the payout wallet the agent actually saw', async () => {
    await db.query("UPDATE users SET payout_phone = '+224620000009', payout_method = 'OM_GN' WHERE id = $1", [seller]);
    await expect(admin.verifyPayout(agent, seller, { verified: true, payoutPhone: '+224660000000' })).rejects.toMatchObject({ response: { code: 'PAYOUT_WALLET_CHANGED' } });
    await expect(admin.verifyPayout(agent, seller, { verified: true, payoutPhone: '+224620000009' })).resolves.toMatchObject({ payoutVerified: true });
  });
});

describe('retool read-only role', () => {
  it('reads the views, including soft overlaps, but not the base tables', async () => {
    const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
    await client.connect();
    try {
      await client.query('SET ROLE retool_ro');
      const { rows } = await client.query('SELECT code, soft_overlaps, document_count FROM retool.parcel_queue');
      expect(rows).toEqual([{ code: 'TGN-000001', soft_overlaps: [], document_count: 0 }]);
      await expect(client.query('SELECT * FROM parcels')).rejects.toMatchObject({ code: '42501' });
      await expect(client.query("UPDATE retool.users SET payout_verified = true")).rejects.toMatchObject({ code: '42501' });
    } finally {
      await client.end();
    }
  });
});
