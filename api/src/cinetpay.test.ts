import { describe, expect, it, vi } from 'vitest';
import { CinetPayClient } from './cinetpay.js';

const json = (body: unknown) => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json' } });

describe('CinetPayClient', () => {
  it('logs in once, reuses the token, and logs in again when CinetPay says it expired', async () => {
    let logins = 0;
    let first = true;
    const http = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      const path = new URL(String(url)).pathname;
      if (path === '/v1/oauth/login') return json({ access_token: `jwt-${++logins}` });
      const auth = (init?.headers as Record<string, string>).authorization;
      if (path === '/v1/payment/TGN-R-2' && first) {
        first = false;
        return json({ code: 1003, status: 'EXPIRED_TOKEN' });
      }
      return json({ code: 200, status: 'SUCCESS', transaction_id: 'cp-1', amount: 1000, currency: 'GNF', auth });
    });
    const client = new CinetPayClient({ baseUrl: 'https://api.cinetpay.test', apiKey: 'sk_test_x', apiPassword: 'pw' }, http as typeof fetch);
    expect((await client.getPayment('TGN-R-1')).raw.auth).toBe('Bearer jwt-1');
    const second = await client.getPayment('TGN-R-2');
    expect(second).toMatchObject({ status: 'SUCCESS', amount: 1000, currency: 'GNF' });
    expect(second.raw.auth).toBe('Bearer jwt-2');
    expect(logins).toBe(2);
  });

  it('sends GNF payment and transfer requests with our merchant ids', async () => {
    const bodies: Record<string, unknown>[] = [];
    const http = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      if (String(url).endsWith('/v1/oauth/login')) return json({ access_token: 'jwt' });
      bodies.push(JSON.parse(String(init?.body)));
      return json({ code: 200, status: 'INITIATED', payment_url: 'https://checkout.test/x', notify_token: 'nt', transaction_id: 'cp-9' });
    });
    const client = new CinetPayClient({ baseUrl: 'https://api.cinetpay.test', apiKey: 'k', apiPassword: 'p' }, http as typeof fetch);
    await expect(client.initPayment({ merchantTransactionId: 'TGN-R-9', amount: 1_000_000, designation: 'Acompte', lang: 'fr', customerId: 5, notifyUrl: 'https://api/n', returnUrl: 'https://api/r' })).resolves.toEqual({
      paymentUrl: 'https://checkout.test/x',
      notifyToken: 'nt',
      transactionId: 'cp-9',
    });
    await client.createTransfer({ merchantTransactionId: 'TGN-P-3', amount: 970_000, phone: '+224620000001', method: 'OM_GN', reason: 'x', notifyUrl: 'https://api/t' });
    expect(bodies[0]).toMatchObject({ currency: 'GNF', merchant_transaction_id: 'TGN-R-9', amount: 1_000_000 });
    expect(bodies[1]).toMatchObject({ currency: 'GNF', merchant_transaction_id: 'TGN-P-3', phone_number: '+224620000001', payment_method: 'OM_GN' });
  });
});
