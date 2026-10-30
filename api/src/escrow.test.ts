import { afterAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createUser, rect, resetDatabase } from '../test/helpers.js';
import type { Staff } from './admin.controller.js';
import type { CinetPayClient, PaymentStatus } from './cinetpay.js';
import { DatabaseService } from './db.js';
import { EscrowService, splitDeposit } from './escrow.service.js';
import { ParcelsService } from './parcels.service.js';
import { StorageService } from './storage.service.js';

/** Stands in for CinetPay: tests decide what the status API says and when transfers fail. */
class FakeGateway {
  payments = new Map<string, PaymentStatus>();
  transfers = new Map<string, string>();
  dropNextTransfer = false;
  initPayment = vi.fn(async (input: { merchantTransactionId: string }) => ({
    paymentUrl: `https://checkout.test/${input.merchantTransactionId}`,
    notifyToken: `nt-${input.merchantTransactionId}`,
    transactionId: `cp-${input.merchantTransactionId}`,
  }));
  getPayment = vi.fn(async (id: string) => this.payments.get(id) ?? { status: 'PENDING', raw: {} });
  createTransfer = vi.fn(async (input: { merchantTransactionId: string }) => {
    if (this.dropNextTransfer) {
      this.dropNextTransfer = false;
      throw new Error('socket hang up');
    }
    if (this.transfers.has(input.merchantTransactionId)) return { code: 1200, status: 'TRANSACTION_EXIST', raw: {} };
    this.transfers.set(input.merchantTransactionId, 'PENDING');
    return { code: 200, status: 'PENDING', transactionId: `cpt-${input.merchantTransactionId}`, notifyToken: `tt-${input.merchantTransactionId}`, raw: {} };
  });
  getTransfer = vi.fn(async (id: string) => (this.transfers.has(id) ? { status: this.transfers.get(id)!, transactionId: `cpt-${id}`, raw: {} } : null));
  paid(id: string, amount = 1_000_000) {
    this.payments.set(id, { status: 'SUCCESS', transactionId: `cp-${id}`, amount, currency: 'GNF', raw: { status: 'SUCCESS' } });
  }
}

const db = new DatabaseService();
let gateway: FakeGateway;
let escrow: EscrowService;
const parcels = new ParcelsService(db, new StorageService());
const admin: Staff = { email: 'admin@terrain.gn', role: 'admin' };
let seller: number;
let buyer: number;
let parcelId: number;

beforeEach(async () => {
  await resetDatabase(db.pool);
  gateway = new FakeGateway();
  escrow = new EscrowService(db, gateway as unknown as CinetPayClient);
  escrow.configured = true;
  seller = await createUser(db.pool, '+224620000001');
  buyer = await createUser(db.pool, '+33612345678');
  await db.query("UPDATE users SET payout_phone = '+224620000001', payout_method = 'OM_GN', payout_verified = true WHERE id = $1", [seller]);
  await db.query("UPDATE users SET payout_phone = '+224660000002', payout_method = 'MTN_GN', payout_verified = true WHERE id = $1", [buyer]);
  const created = await parcels.create(seller, {
    boundary: { corners: rect(0, 0, 20, 25), crs: 'EPSG:4326' },
    title: 'Terrain',
    region: 'conakry',
    prefecture: 'Ratoma',
    locality: 'Kipé',
    priceGnf: 150_000_000,
    depositGnf: 1_000_000,
  });
  parcelId = created.id;
  await db.query("UPDATE parcels SET status = 'verified', verified_by = 'agent@terrain.gn', verified_at = now() WHERE id = $1", [parcelId]);
});
afterAll(() => db.onModuleDestroy());

const parcelStatus = async () => (await db.query('SELECT status FROM parcels WHERE id = $1', [parcelId])).rows[0]!.status;
const webhook = (id: number, token = `nt-TGN-R-${id}`) => escrow.paymentWebhook({ merchant_transaction_id: `TGN-R-${id}`, notify_token: token });

async function heldReservation() {
  const reservation = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
  gateway.paid(`TGN-R-${reservation.id}`);
  await webhook(reservation.id);
  return reservation;
}

describe('reservations', () => {
  it('creates a pending reservation with a checkout link, idempotently', async () => {
    const first = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    expect(first).toMatchObject({ status: 'pending_payment', amountGnf: 1_000_000, paymentUrl: `https://checkout.test/TGN-R-${first.id}` });
    expect(await escrow.reserve(buyer, parcelId, 'reserve-key-1')).toMatchObject({ id: first.id });
    expect(gateway.initPayment).toHaveBeenCalledTimes(1);
  });

  it('blocks own parcels, a second buyer while one is pending, and deposits above the gateway limit', async () => {
    await expect(escrow.reserve(seller, parcelId, 'reserve-key-1')).rejects.toMatchObject({ response: { code: 'OWN_PARCEL' } });
    await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    const other = await createUser(db.pool, '+224620000003');
    await expect(escrow.reserve(other, parcelId, 'reserve-key-2')).rejects.toMatchObject({ response: { code: 'PARCEL_NOT_AVAILABLE' } });
    await db.query("UPDATE reservations SET status = 'failed'");
    await db.query('UPDATE parcels SET deposit_gnf = 2000000 WHERE id = $1', [parcelId]);
    await expect(escrow.reserve(other, parcelId, 'reserve-key-3')).rejects.toMatchObject({ response: { code: 'DEPOSIT_ABOVE_GATEWAY_LIMIT' } });
  });

  it('marks the reservation failed when CinetPay cannot start the payment', async () => {
    gateway.initPayment.mockRejectedValueOnce(new Error('timeout'));
    await expect(escrow.reserve(buyer, parcelId, 'reserve-key-1')).rejects.toMatchObject({ response: { code: 'PAYMENT_PROVIDER_UNAVAILABLE' } });
    expect((await escrow.mine(buyer)).items[0]).toMatchObject({ status: 'failed' });
  });

  it('refuses a webhook with the wrong notify token and changes nothing', async () => {
    const reservation = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    gateway.paid(`TGN-R-${reservation.id}`);
    await expect(webhook(reservation.id, 'forged')).rejects.toMatchObject({ status: 401 });
    expect(gateway.getPayment).not.toHaveBeenCalled();
    expect(await parcelStatus()).toBe('verified');
  });

  it('trusts the status API over the webhook: no change while CinetPay still says pending', async () => {
    const reservation = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    await webhook(reservation.id);
    expect((await escrow.get(buyer, reservation.id)).status).toBe('pending_payment');
  });

  it('holds the deposit, reserves the parcel, and ignores duplicate webhooks', async () => {
    const reservation = await heldReservation();
    await webhook(reservation.id);
    await webhook(reservation.id);
    expect(await escrow.get(buyer, reservation.id)).toMatchObject({ status: 'held', paymentUrl: null });
    expect(await parcelStatus()).toBe('reserved');
    const { rows } = await db.query("SELECT count(*)::int AS n FROM audit_events WHERE action = 'reservation.held'");
    expect(rows[0]!.n).toBe(1);
  });

  it('settles on poll when the webhook never arrives', async () => {
    const reservation = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    gateway.paid(`TGN-R-${reservation.id}`);
    expect((await escrow.get(buyer, reservation.id)).status).toBe('held');
  });

  it('sends an amount mismatch to review instead of holding it', async () => {
    const reservation = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    gateway.paid(`TGN-R-${reservation.id}`, 5_000);
    await webhook(reservation.id);
    expect(await escrow.get(buyer, reservation.id)).toMatchObject({ status: 'needs_review', reviewReason: 'AMOUNT_MISMATCH' });
    expect(await parcelStatus()).toBe('verified');
  });

  it('lets a late payment win a free parcel but not one someone else holds', async () => {
    const late = await escrow.reserve(buyer, parcelId, 'reserve-key-1');
    await db.query("UPDATE reservations SET expires_at = now() - interval '1 minute' WHERE id = $1", [late.id]);
    expect((await escrow.get(buyer, late.id)).status).toBe('expired');
    gateway.paid(`TGN-R-${late.id}`);
    await webhook(late.id);
    expect((await escrow.get(buyer, late.id)).status).toBe('held');

    await db.query("UPDATE reservations SET status = 'failed' WHERE id = $1", [late.id]);
    await db.query("UPDATE parcels SET status = 'verified' WHERE id = $1", [parcelId]);
    const other = await createUser(db.pool, '+224620000003');
    const lost = await escrow.reserve(other, parcelId, 'reserve-key-4');
    await db.query("UPDATE reservations SET status = 'expired' WHERE id = $1", [lost.id]);
    const winner = await escrow.reserve(buyer, parcelId, 'reserve-key-5');
    gateway.paid(`TGN-R-${winner.id}`);
    await webhook(winner.id);
    gateway.paid(`TGN-R-${lost.id}`);
    await webhook(lost.id);
    expect(await escrow.get(other, lost.id)).toMatchObject({ status: 'needs_review', reviewReason: 'PARCEL_UNAVAILABLE' });
  });
});

describe('payouts', () => {
  it('splits the fee and pays the seller, then marks the parcel sold', async () => {
    const reservation = await heldReservation();
    const payout = await escrow.release(admin, reservation.id);
    const { fee, payout: net } = splitDeposit(1_000_000);
    expect(payout).toMatchObject({ kind: 'release', status: 'sent', amountGnf: net, feeGnf: fee, phone: '+224620000001', method: 'OM_GN' });
    expect(net + fee).toBe(1_000_000);
    gateway.transfers.set(`TGN-P-${payout.id}`, 'SUCCESS');
    await escrow.transferWebhook({ merchant_transaction_id: `TGN-P-${payout.id}`, notify_token: `tt-TGN-P-${payout.id}` });
    expect((await escrow.get(buyer, reservation.id)).status).toBe('released');
    expect(await parcelStatus()).toBe('sold');
  });

  it('enforces four eyes, a verified wallet, and one live payout', async () => {
    const reservation = await heldReservation();
    await expect(escrow.release({ email: 'agent@terrain.gn', role: 'admin' }, reservation.id)).rejects.toMatchObject({ response: { code: 'FOUR_EYES_REQUIRED' } });
    await db.query('UPDATE users SET payout_verified = false WHERE id = $1', [seller]);
    await expect(escrow.release(admin, reservation.id)).rejects.toMatchObject({ response: { code: 'PAYOUT_WALLET_UNVERIFIED' } });
    await db.query('UPDATE users SET payout_verified = true WHERE id = $1', [seller]);
    await escrow.release(admin, reservation.id);
    await expect(escrow.release(admin, reservation.id)).rejects.toMatchObject({ response: { code: 'PAYOUT_EXISTS' } });
    await expect(escrow.refund(admin, reservation.id)).rejects.toMatchObject({ response: { code: 'PAYOUT_EXISTS' } });
  });

  it('refunds the buyer and puts the parcel back on the market', async () => {
    const reservation = await heldReservation();
    const payout = await escrow.refund(admin, reservation.id);
    expect(payout).toMatchObject({ kind: 'refund', amountGnf: 1_000_000, feeGnf: 0, phone: '+224660000002' });
    gateway.transfers.set(`TGN-P-${payout.id}`, 'SUCCESS');
    await escrow.reconcilePayout(payout.id);
    expect((await escrow.get(buyer, reservation.id)).status).toBe('refunded');
    expect(await parcelStatus()).toBe('verified');
  });

  it('keeps the deposit held when a transfer fails, and allows a retry', async () => {
    const reservation = await heldReservation();
    const first = await escrow.release(admin, reservation.id);
    gateway.transfers.set(`TGN-P-${first.id}`, 'FAILED');
    expect(await escrow.reconcilePayout(first.id)).toMatchObject({ status: 'failed' });
    expect((await escrow.get(buyer, reservation.id)).status).toBe('held');
    expect(await escrow.release(admin, reservation.id)).toMatchObject({ status: 'sent' });
  });

  it('recovers a payout whose transfer call was lost, without paying twice', async () => {
    const reservation = await heldReservation();
    gateway.dropNextTransfer = true;
    const stuck = await escrow.release(admin, reservation.id);
    expect(stuck.status).toBe('pending');
    expect(await escrow.reconcilePayout(stuck.id)).toMatchObject({ status: 'sent' });
    expect(await escrow.reconcilePayout(stuck.id)).toMatchObject({ status: 'sent' });
    expect(gateway.transfers.size).toBe(1);
    expect(gateway.createTransfer).toHaveBeenCalledTimes(2);
  });
});
