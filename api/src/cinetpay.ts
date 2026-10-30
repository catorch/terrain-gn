import { config } from './config.js';

// CinetPay v1 API as described by CinetPay's official SDKs (github.com/cinetpay). The public docs were
// unreachable during design: confirm field names and status codes with sandbox keys before go-live.
// This file is the only place that knows the wire format.

export type ProviderStatus = 'SUCCESS' | 'FAILED' | 'PENDING' | 'INITIATED' | 'EXPIRED' | string;
export const FINAL_STATUSES = new Set(['SUCCESS', 'FAILED', 'EXPIRED']);

const EXPIRED_TOKEN = 1003;
export const TRANSACTION_EXISTS = 1200;
const TOKEN_TTL_MS = 23 * 3_600_000;

type Fetch = typeof fetch;
type Json = Record<string, unknown>;

export class CinetPayError extends Error {
  constructor(
    message: string,
    readonly code?: number,
  ) {
    super(message);
  }
}

export interface PaymentStatus {
  status: ProviderStatus;
  transactionId?: string;
  amount?: number;
  currency?: string;
  raw: Json;
}

export class CinetPayClient {
  private token?: { value: string; expiresAt: number };

  constructor(
    private readonly options = { baseUrl: config.CINETPAY_BASE_URL, apiKey: config.CINETPAY_API_KEY ?? '', apiPassword: config.CINETPAY_API_PASSWORD ?? '' },
    private readonly http: Fetch = (input, init) => fetch(input, init),
  ) {}

  private async login() {
    const body = await this.call('POST', '/v1/oauth/login', { api_key: this.options.apiKey, api_password: this.options.apiPassword }, false);
    if (typeof body.access_token !== 'string') throw new CinetPayError('CinetPay login failed', Number(body.code));
    this.token = { value: body.access_token, expiresAt: Date.now() + TOKEN_TTL_MS };
    return this.token.value;
  }

  private async call(method: 'GET' | 'POST', path: string, payload?: Json, authenticated = true): Promise<Json> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const token = authenticated ? (this.token && this.token.expiresAt > Date.now() ? this.token.value : await this.login()) : undefined;
      const response = await this.http(`${this.options.baseUrl}${path}`, {
        method,
        headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: payload ? JSON.stringify(payload) : undefined,
        signal: AbortSignal.timeout(15_000),
      });
      const body = (await response.json().catch(() => ({}))) as Json;
      if (authenticated && Number(body.code) === EXPIRED_TOKEN && attempt === 0) {
        this.token = undefined;
        continue;
      }
      return body;
    }
    throw new CinetPayError('CinetPay token kept expiring', EXPIRED_TOKEN);
  }

  async initPayment(input: { merchantTransactionId: string; amount: number; designation: string; lang: 'fr' | 'en'; customerId: number; notifyUrl: string; returnUrl: string }) {
    const body = await this.call('POST', '/v1/payment', {
      currency: 'GNF',
      merchant_transaction_id: input.merchantTransactionId,
      amount: input.amount,
      lang: input.lang,
      designation: input.designation,
      // Users sign in by phone and have no email or legal name on file; placeholders until CinetPay confirms what it validates.
      client_email: `u${input.customerId}@${new URL(config.PUBLIC_API_URL).hostname}`,
      client_first_name: 'Client',
      client_last_name: `TGN${input.customerId}`,
      success_url: input.returnUrl,
      failed_url: input.returnUrl,
      notify_url: input.notifyUrl,
      channel: 'PUSH',
    });
    if (typeof body.payment_url !== 'string' || typeof body.notify_token !== 'string') throw new CinetPayError('Payment could not be initialized', Number(body.code));
    return { paymentUrl: body.payment_url, notifyToken: body.notify_token, transactionId: String(body.transaction_id ?? '') };
  }

  async getPayment(merchantTransactionId: string): Promise<PaymentStatus> {
    const body = await this.call('GET', `/v1/payment/${encodeURIComponent(merchantTransactionId)}`);
    return {
      status: String(body.status ?? 'UNKNOWN'),
      transactionId: body.transaction_id === undefined ? undefined : String(body.transaction_id),
      amount: body.amount === undefined ? undefined : Number(body.amount),
      currency: body.currency === undefined ? undefined : String(body.currency),
      raw: body,
    };
  }

  async createTransfer(input: { merchantTransactionId: string; amount: number; phone: string; method: string; reason: string; notifyUrl: string }) {
    const body = await this.call('POST', '/v1/transfer', {
      currency: 'GNF',
      merchant_transaction_id: input.merchantTransactionId,
      phone_number: input.phone,
      amount: input.amount,
      payment_method: input.method,
      reason: input.reason,
      notify_url: input.notifyUrl,
    });
    return { code: Number(body.code), status: String(body.status ?? 'UNKNOWN'), transactionId: body.transaction_id === undefined ? undefined : String(body.transaction_id), notifyToken: typeof body.notify_token === 'string' ? body.notify_token : undefined, raw: body };
  }

  /** null when CinetPay has no transfer under this id (the send never reached them). */
  async getTransfer(merchantTransactionId: string) {
    const body = await this.call('GET', `/v1/transfer/${encodeURIComponent(merchantTransactionId)}`);
    if (body.status === undefined) return null;
    return { status: String(body.status), transactionId: body.transaction_id === undefined ? undefined : String(body.transaction_id), raw: body };
  }
}
