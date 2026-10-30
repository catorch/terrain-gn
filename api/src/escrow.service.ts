import { timingSafeEqual } from 'node:crypto';
import { Inject, Injectable, Logger } from '@nestjs/common';
import type { DatabaseError, PoolClient } from 'pg';
import type { Staff } from './admin.controller.js';
import { CinetPayClient, FINAL_STATUSES, TRANSACTION_EXISTS, type PaymentStatus } from './cinetpay.js';
import { cinetpayConfigured, config } from './config.js';
import { audit, DatabaseService } from './db.js';
import { ApiError } from './errors.js';

const PAYMENT_WINDOW_MINUTES = 30;

interface Reservation {
  id: number;
  merchant_tx_id: string;
  parcel_id: number;
  buyer_id: number;
  amount_gnf: number;
  status: string;
  review_reason: string | null;
  notify_token: string | null;
  payment_url: string | null;
  expires_at: Date;
  paid_at: Date | null;
  created_at: Date;
}

interface Payout {
  id: number;
  merchant_tx_id: string;
  reservation_id: number;
  kind: 'release' | 'refund';
  amount_gnf: number;
  fee_gnf: number;
  phone: string;
  method: string;
  status: string;
  notify_token: string | null;
}

const view = (r: Reservation) => ({
  id: r.id,
  parcelId: r.parcel_id,
  amountGnf: r.amount_gnf,
  status: r.status,
  reviewReason: r.review_reason,
  paymentUrl: r.status === 'pending_payment' ? r.payment_url : null,
  expiresAt: r.expires_at,
  paidAt: r.paid_at,
  createdAt: r.created_at,
});

type PayoutView = ReturnType<typeof payoutView>;

const payoutView = (p: Payout) => ({ id: p.id, reservationId: p.reservation_id, kind: p.kind, amountGnf: p.amount_gnf, feeGnf: p.fee_gnf, status: p.status, phone: p.phone, method: p.method });

export function tokensMatch(expected: string | null, presented: unknown) {
  if (!expected || typeof presented !== 'string') return false;
  const [a, b] = [Buffer.from(expected), Buffer.from(presented)];
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Platform fee in basis points, rounded down so the seller is never short-changed by rounding. */
export const splitDeposit = (amount: number, bps = config.PLATFORM_FEE_BPS) => {
  const fee = Math.floor((amount * bps) / 10_000);
  return { fee, payout: amount - fee };
};

/**
 * Every state change locks the parcel first and the reservation second, the same order reserve() uses,
 * so a webhook and a new reservation for the same plot cannot deadlock.
 */
@Injectable()
export class EscrowService {
  private readonly log = new Logger('Escrow');

  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CinetPayClient) private readonly cinetpay: CinetPayClient,
  ) {}

  configured = cinetpayConfigured;

  private requireGateway() {
    if (!this.configured) throw new ApiError(503, 'PAYMENTS_NOT_CONFIGURED');
  }

  async reserve(buyerId: number, parcelId: number, idempotencyKey: string) {
    this.requireGateway();
    const prior = await this.db.query<Reservation>('SELECT * FROM reservations WHERE buyer_id = $1 AND idempotency_key = $2', [buyerId, idempotencyKey]);
    if (prior.rows[0]) return view(prior.rows[0]);
    const reservation = await this.db.transaction(async (client) => {
      const { rows } = await client.query<{ owner_id: number; status: string; deposit_gnf: number | null; code: string }>(
        'SELECT owner_id, status, deposit_gnf, code FROM parcels WHERE id = $1 FOR UPDATE',
        [parcelId],
      );
      const parcel = rows[0];
      if (!parcel || parcel.status !== 'verified') throw new ApiError(409, 'PARCEL_NOT_AVAILABLE');
      if (parcel.owner_id === buyerId) throw new ApiError(409, 'OWN_PARCEL');
      if (!parcel.deposit_gnf) throw new ApiError(409, 'NO_DEPOSIT');
      if (parcel.deposit_gnf > config.CINETPAY_MAX_AMOUNT_GNF) throw new ApiError(422, 'DEPOSIT_ABOVE_GATEWAY_LIMIT', { maxGnf: config.CINETPAY_MAX_AMOUNT_GNF });
      await client.query("UPDATE reservations SET status = 'expired' WHERE parcel_id = $1 AND status = 'pending_payment' AND expires_at < now()", [parcelId]);
      const inserted = await client
        .query<Reservation>(
          `INSERT INTO reservations (parcel_id, buyer_id, amount_gnf, idempotency_key, expires_at)
           VALUES ($1, $2, $3, $4, now() + make_interval(mins => $5)) RETURNING *`,
          [parcelId, buyerId, parcel.deposit_gnf, idempotencyKey, PAYMENT_WINDOW_MINUTES],
        )
        .catch((error: DatabaseError) => {
          if (error.constraint === 'reservations_one_active') throw new ApiError(409, 'PARCEL_NOT_AVAILABLE');
          throw error;
        });
      await audit(client, `user:${buyerId}`, 'reservation.created', 'reservation', inserted.rows[0]!.id, { parcelId, amountGnf: parcel.deposit_gnf });
      return { ...inserted.rows[0]!, code: parcel.code };
    });
    const { locale } = (await this.db.query<{ locale: 'fr' | 'en' }>('SELECT locale FROM users WHERE id = $1', [buyerId])).rows[0]!;
    try {
      const payment = await this.cinetpay.initPayment({
        merchantTransactionId: reservation.merchant_tx_id,
        amount: reservation.amount_gnf,
        designation: `${locale === 'fr' ? 'Acompte terrain' : 'Plot deposit'} ${reservation.code}`,
        lang: locale,
        customerId: buyerId,
        notifyUrl: `${config.PUBLIC_API_URL}/v1/webhooks/cinetpay/payment`,
        returnUrl: `${config.PUBLIC_API_URL}/v1/payments/return`,
      });
      const { rows } = await this.db.query<Reservation>(
        'UPDATE reservations SET payment_url = $2, notify_token = $3, provider_tx_id = $4 WHERE id = $1 RETURNING *',
        [reservation.id, payment.paymentUrl, payment.notifyToken, payment.transactionId || null],
      );
      return view(rows[0]!);
    } catch (error) {
      this.log.error(`initPayment failed for ${reservation.merchant_tx_id}: ${(error as Error).message}`);
      await this.db.query("UPDATE reservations SET status = 'failed', review_reason = 'INIT_FAILED' WHERE id = $1", [reservation.id]);
      throw new ApiError(502, 'PAYMENT_PROVIDER_UNAVAILABLE');
    }
  }

  async get(buyerId: number, id: number) {
    const { rows } = await this.db.query<Reservation>('SELECT * FROM reservations WHERE id = $1 AND buyer_id = $2', [id, buyerId]);
    const reservation = rows[0];
    if (!reservation) throw new ApiError(404, 'RESERVATION_NOT_FOUND');
    // Pull on read (R7.6): a webhook lost on the way to us must not leave the buyer staring at "pending".
    if (reservation.status === 'pending_payment' && this.configured) return view((await this.settlePayment(reservation.merchant_tx_id)) ?? reservation);
    return view(reservation);
  }

  async mine(buyerId: number) {
    const { rows } = await this.db.query<Reservation>('SELECT * FROM reservations WHERE buyer_id = $1 ORDER BY id DESC', [buyerId]);
    return { items: rows.map(view) };
  }

  /** Webhooks are only a hint that something changed; the status API decides what (R7.4). */
  async paymentWebhook(body: Record<string, unknown>) {
    const merchantTxId = String(body.merchant_transaction_id ?? '');
    const { rows } = await this.db.query<Reservation>('SELECT * FROM reservations WHERE merchant_tx_id = $1', [merchantTxId]);
    if (!rows[0]) return { received: true }; // not ours; answering 200 stops CinetPay retrying
    if (!tokensMatch(rows[0].notify_token, body.notify_token)) throw new ApiError(401, 'NOTIFY_TOKEN_INVALID');
    await this.settlePayment(merchantTxId);
    return { received: true };
  }

  async settlePayment(merchantTxId: string) {
    const payment = await this.cinetpay.getPayment(merchantTxId);
    return this.db.transaction(async (client) => {
      const reservation = await this.lockReservation(client, 'merchant_tx_id', merchantTxId);
      if (!reservation) return null;
      if (!FINAL_STATUSES.has(payment.status)) {
        if (reservation.status === 'pending_payment' && reservation.expires_at < new Date()) return this.setStatus(client, reservation, 'expired');
        return reservation;
      }
      const fresh = await client.query(
        'INSERT INTO payment_events (provider_tx_id, status, reservation_id, raw) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING id',
        [payment.transactionId ?? merchantTxId, payment.status, reservation.id, payment.raw],
      );
      if (!fresh.rows[0] || !['pending_payment', 'expired'].includes(reservation.status)) return reservation; // duplicate or already settled
      if (payment.status !== 'SUCCESS') return reservation.status === 'pending_payment' ? this.setStatus(client, reservation, 'failed') : reservation;
      return this.acceptPayment(client, reservation, payment);
    });
  }

  private async acceptPayment(client: PoolClient, reservation: Reservation, payment: PaymentStatus) {
    await client.query('UPDATE reservations SET paid_at = now() WHERE id = $1', [reservation.id]);
    if ((payment.amount !== undefined && payment.amount !== reservation.amount_gnf) || (payment.currency !== undefined && payment.currency !== 'GNF')) {
      return this.setStatus(client, reservation, 'needs_review', 'AMOUNT_MISMATCH', { paid: payment.amount, currency: payment.currency });
    }
    // A late payment (after expiry) still wins the plot if nobody else holds it (R7.7).
    await client.query("UPDATE reservations SET status = 'expired' WHERE parcel_id = $1 AND id <> $2 AND status = 'pending_payment' AND expires_at < now()", [reservation.parcel_id, reservation.id]);
    const other = await client.query("SELECT 1 FROM reservations WHERE parcel_id = $1 AND id <> $2 AND status IN ('pending_payment', 'held')", [reservation.parcel_id, reservation.id]);
    if (other.rows[0]) return this.setStatus(client, reservation, 'needs_review', 'PARCEL_UNAVAILABLE');
    const parcel = await client.query("UPDATE parcels SET status = 'reserved' WHERE id = $1 AND status = 'verified' RETURNING id", [reservation.parcel_id]);
    if (!parcel.rows[0]) return this.setStatus(client, reservation, 'needs_review', 'PARCEL_UNAVAILABLE');
    return this.setStatus(client, reservation, 'held');
  }

  private async setStatus(client: PoolClient, reservation: Reservation, status: string, reason: string | null = null, data: Record<string, unknown> = {}) {
    const { rows } = await client.query<Reservation>('UPDATE reservations SET status = $2, review_reason = $3 WHERE id = $1 RETURNING *', [reservation.id, status, reason]);
    await audit(client, 'cinetpay', `reservation.${status}`, 'reservation', reservation.id, { from: reservation.status, reason, ...data });
    return rows[0]!;
  }

  private async lockReservation(client: PoolClient, column: 'id' | 'merchant_tx_id', value: number | string) {
    const found = await client.query<{ parcel_id: number }>(`SELECT parcel_id FROM reservations WHERE ${column} = $1`, [value]);
    if (!found.rows[0]) return undefined;
    await client.query('SELECT 1 FROM parcels WHERE id = $1 FOR UPDATE', [found.rows[0].parcel_id]);
    return (await client.query<Reservation>(`SELECT * FROM reservations WHERE ${column} = $1 FOR UPDATE`, [value])).rows[0];
  }

  /** Pays the seller once the deal is done (R7.8): admin only, never the agent who verified the plot. */
  async release(staff: Staff, reservationId: number) {
    this.requireGateway();
    const payout = await this.db.transaction(async (client) => {
      const reservation = await this.lockReservation(client, 'id', reservationId);
      if (!reservation) throw new ApiError(404, 'RESERVATION_NOT_FOUND');
      if (reservation.status !== 'held') throw new ApiError(409, 'INVALID_STATUS', { status: reservation.status });
      const { rows } = await client.query<{ verified_by: string | null; payout_phone: string | null; payout_method: string | null; payout_verified: boolean }>(
        'SELECT p.verified_by, u.payout_phone, u.payout_method, u.payout_verified FROM parcels p JOIN users u ON u.id = p.owner_id WHERE p.id = $1',
        [reservation.parcel_id],
      );
      const seller = rows[0]!;
      if (seller.verified_by === staff.email) throw new ApiError(403, 'FOUR_EYES_REQUIRED');
      if (!seller.payout_verified || !seller.payout_phone || !seller.payout_method) throw new ApiError(409, 'PAYOUT_WALLET_UNVERIFIED');
      const { fee, payout } = splitDeposit(reservation.amount_gnf);
      return this.insertPayout(client, staff, reservation, 'release', payout, fee, seller.payout_phone, seller.payout_method);
    });
    return this.sendPayout(payout);
  }

  /** Returns the deposit to the buyer's verified wallet: a held deposit, or one that needs review. */
  async refund(staff: Staff, reservationId: number) {
    this.requireGateway();
    const payout = await this.db.transaction(async (client) => {
      const reservation = await this.lockReservation(client, 'id', reservationId);
      if (!reservation) throw new ApiError(404, 'RESERVATION_NOT_FOUND');
      if (!(reservation.status === 'held' || (reservation.status === 'needs_review' && reservation.paid_at))) throw new ApiError(409, 'INVALID_STATUS', { status: reservation.status });
      const { rows } = await client.query<{ payout_phone: string | null; payout_method: string | null; payout_verified: boolean }>(
        'SELECT payout_phone, payout_method, payout_verified FROM users WHERE id = $1',
        [reservation.buyer_id],
      );
      const buyer = rows[0]!;
      if (!buyer.payout_verified || !buyer.payout_phone || !buyer.payout_method) throw new ApiError(409, 'PAYOUT_WALLET_UNVERIFIED');
      return this.insertPayout(client, staff, reservation, 'refund', reservation.amount_gnf, 0, buyer.payout_phone, buyer.payout_method);
    });
    return this.sendPayout(payout);
  }

  private async insertPayout(client: PoolClient, staff: Staff, reservation: Reservation, kind: 'release' | 'refund', amount: number, fee: number, phone: string, method: string) {
    const { rows } = await client
      .query<Payout>(
        `INSERT INTO payouts (reservation_id, kind, amount_gnf, fee_gnf, phone, method, created_by) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [reservation.id, kind, amount, fee, phone, method, staff.email],
      )
      .catch((error: DatabaseError) => {
        if (error.constraint === 'payouts_one_active') throw new ApiError(409, 'PAYOUT_EXISTS');
        throw error;
      });
    await audit(client, `staff:${staff.email}`, `payout.${kind}_requested`, 'reservation', reservation.id, { payoutId: rows[0]!.id, amountGnf: amount, feeGnf: fee, phone, method });
    return rows[0]!;
  }

  /**
   * The payout row is committed as `pending` before CinetPay is called. If the process dies in between,
   * reconcile() finds the row and re-sends under the same merchant id, which CinetPay refuses to pay twice.
   */
  private async sendPayout(payout: Payout): Promise<PayoutView> {
    try {
      const transfer = await this.cinetpay.createTransfer({
        merchantTransactionId: payout.merchant_tx_id,
        amount: payout.amount_gnf,
        phone: payout.phone,
        method: payout.method,
        reason: `${payout.kind === 'release' ? 'Paiement terrain' : 'Remboursement acompte'} TGN-R-${payout.reservation_id}`,
        notifyUrl: `${config.PUBLIC_API_URL}/v1/webhooks/cinetpay/transfer`,
      });
      if (transfer.code === TRANSACTION_EXISTS) return this.reconcilePayout(payout.id);
      if (transfer.status === 'FAILED') return this.applyTransfer(payout.id, { status: 'FAILED', raw: transfer.raw });
      await this.db.query("UPDATE payouts SET status = 'sent', provider_tx_id = $2, notify_token = $3, updated_at = now() WHERE id = $1 AND status = 'pending'", [
        payout.id,
        transfer.transactionId ?? null,
        transfer.notifyToken ?? null,
      ]);
      if (transfer.status === 'SUCCESS') return this.applyTransfer(payout.id, { status: 'SUCCESS', transactionId: transfer.transactionId, raw: transfer.raw });
    } catch (error) {
      this.log.error(`createTransfer failed for ${payout.merchant_tx_id}, left pending for reconcile: ${(error as Error).message}`);
    }
    return payoutView((await this.db.query<Payout>('SELECT * FROM payouts WHERE id = $1', [payout.id])).rows[0]!);
  }

  async reconcilePayout(payoutId: number): Promise<PayoutView> {
    this.requireGateway();
    const { rows } = await this.db.query<Payout>('SELECT * FROM payouts WHERE id = $1', [payoutId]);
    const payout = rows[0];
    if (!payout) throw new ApiError(404, 'PAYOUT_NOT_FOUND');
    if (payout.status === 'succeeded' || payout.status === 'failed') return payoutView(payout);
    const transfer = await this.cinetpay.getTransfer(payout.merchant_tx_id);
    if (!transfer) return payout.status === 'pending' ? this.sendPayout(payout) : payoutView(payout);
    if (payout.status === 'pending') await this.db.query("UPDATE payouts SET status = 'sent', provider_tx_id = $2, updated_at = now() WHERE id = $1", [payout.id, transfer.transactionId ?? null]);
    return FINAL_STATUSES.has(transfer.status) ? this.applyTransfer(payout.id, transfer) : payoutView({ ...payout, status: 'sent' });
  }

  async transferWebhook(body: Record<string, unknown>) {
    const { rows } = await this.db.query<Payout>('SELECT * FROM payouts WHERE merchant_tx_id = $1', [String(body.merchant_transaction_id ?? '')]);
    if (!rows[0]) return { received: true };
    if (!tokensMatch(rows[0].notify_token, body.notify_token)) throw new ApiError(401, 'NOTIFY_TOKEN_INVALID');
    await this.reconcilePayout(rows[0].id);
    return { received: true };
  }

  private async applyTransfer(payoutId: number, transfer: { status: string; transactionId?: string; raw: Record<string, unknown> }) {
    return this.db.transaction(async (client) => {
      const reservationId = (await client.query<{ reservation_id: number }>('SELECT reservation_id FROM payouts WHERE id = $1', [payoutId])).rows[0]!.reservation_id;
      const reservation = (await this.lockReservation(client, 'id', reservationId))!;
      const payout = (await client.query<Payout>('SELECT * FROM payouts WHERE id = $1 FOR UPDATE', [payoutId])).rows[0]!;
      if (payout.status === 'succeeded' || payout.status === 'failed') return payoutView(payout);
      await client.query('INSERT INTO payment_events (provider_tx_id, status, payout_id, raw) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING', [
        transfer.transactionId ?? payout.merchant_tx_id,
        transfer.status,
        payout.id,
        transfer.raw,
      ]);
      if (transfer.status !== 'SUCCESS') {
        // The deposit stays held; an admin can retry, which creates a new payout row.
        const failed = await client.query<Payout>("UPDATE payouts SET status = 'failed', failure_reason = $2, updated_at = now() WHERE id = $1 RETURNING *", [payout.id, transfer.status]);
        await audit(client, 'cinetpay', `payout.${payout.kind}_failed`, 'reservation', reservation.id, { payoutId: payout.id });
        return payoutView(failed.rows[0]!);
      }
      const done = await client.query<Payout>("UPDATE payouts SET status = 'succeeded', updated_at = now() WHERE id = $1 RETURNING *", [payout.id]);
      await client.query('UPDATE reservations SET status = $2 WHERE id = $1', [reservation.id, payout.kind === 'release' ? 'released' : 'refunded']);
      if (payout.kind === 'release') await client.query("UPDATE parcels SET status = 'sold' WHERE id = $1", [reservation.parcel_id]);
      else if (reservation.status === 'held') await client.query("UPDATE parcels SET status = 'verified' WHERE id = $1 AND status = 'reserved'", [reservation.parcel_id]);
      await audit(client, 'cinetpay', `payout.${payout.kind}_succeeded`, 'reservation', reservation.id, { payoutId: payout.id, amountGnf: payout.amount_gnf });
      return payoutView(done.rows[0]!);
    });
  }
}
