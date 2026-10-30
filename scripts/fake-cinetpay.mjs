// Local stand-in for the CinetPay v1 endpoints that api/src/cinetpay.ts calls, so the escrow flow can run
// end to end before merchant keys exist. Dev tooling only: never point a deployed API at it.
// Usage: node scripts/fake-cinetpay.mjs  (then run the API with CINETPAY_BASE_URL=http://localhost:9300)
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';

const PORT = Number(process.env.PORT ?? 9300);
const BASE = `http://localhost:${PORT}`;
const payments = new Map();
const transfers = new Map();
const token = () => randomBytes(12).toString('hex');

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'content-type': type });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}

async function readBody(req) {
  let raw = '';
  for await (const chunk of req) raw += chunk;
  try {
    return JSON.parse(raw || '{}');
  } catch {
    return Object.fromEntries(new URLSearchParams(raw));
  }
}

function notify(item) {
  const body = JSON.stringify({ merchant_transaction_id: item.merchant_transaction_id, transaction_id: item.transaction_id, notify_token: item.notify_token });
  return fetch(item.notify_url, { method: 'POST', headers: { 'content-type': 'application/json' }, body }).catch((error) => console.error('notify failed:', error.message));
}

createServer(async (req, res) => {
  const url = new URL(req.url, BASE);
  const [, a, b, c] = url.pathname.split('/').map(decodeURIComponent);
  console.log(req.method, url.pathname);

  if (req.method === 'POST' && url.pathname === '/v1/oauth/login') return send(res, 200, { code: 200, access_token: 'fake-jwt' });

  if (req.method === 'POST' && url.pathname === '/v1/payment') {
    const body = await readBody(req);
    if (payments.has(body.merchant_transaction_id)) return send(res, 200, { code: 1200, status: 'TRANSACTION_EXIST' });
    const item = { ...body, status: 'INITIATED', transaction_id: `CP${token().slice(0, 10)}`, notify_token: token() };
    payments.set(body.merchant_transaction_id, item);
    return send(res, 200, { code: 200, status: 'INITIATED', payment_url: `${BASE}/checkout/${encodeURIComponent(body.merchant_transaction_id)}`, payment_token: token(), notify_token: item.notify_token, transaction_id: item.transaction_id, merchant_transaction_id: body.merchant_transaction_id });
  }

  if (req.method === 'GET' && a === 'v1' && b === 'payment' && c) {
    const item = payments.get(c);
    if (!item) return send(res, 404, { code: 404, message: 'not found' });
    return send(res, 200, { code: item.status === 'SUCCESS' ? 100 : 2002, status: item.status, amount: Number(item.amount), currency: item.currency, transaction_id: item.transaction_id, merchant_transaction_id: item.merchant_transaction_id });
  }

  if (a === 'checkout' && b) {
    const item = payments.get(b);
    if (!item) return send(res, 404, 'Unknown payment', 'text/plain');
    if (req.method === 'POST') {
      item.status = c === 'pay' ? 'SUCCESS' : 'FAILED';
      await notify(item);
      res.writeHead(303, { location: item.success_url });
      return res.end();
    }
    const amount = Number(item.amount).toLocaleString('fr-FR');
    return send(res, 200, `<!doctype html><meta name="viewport" content="width=device-width"><title>Fake CinetPay</title>
<body style="font-family:sans-serif;padding:24px;max-width:420px;margin:auto"><p style="color:#b45309">Local fake checkout — no money moves</p>
<h2>${item.designation}</h2><p style="font-size:28px;font-weight:700">${amount} GNF</p>
<form method="post" action="/checkout/${encodeURIComponent(b)}/pay"><button style="font-size:18px;padding:14px;width:100%;background:#ff7900;color:#fff;border:0;border-radius:10px">Payer avec Orange Money</button></form>
<form method="post" action="/checkout/${encodeURIComponent(b)}/fail"><button style="margin-top:12px;width:100%;padding:10px">Simuler un échec</button></form>`, 'text/html; charset=utf-8');
  }

  if (req.method === 'POST' && url.pathname === '/v1/transfer') {
    const body = await readBody(req);
    if (transfers.has(body.merchant_transaction_id)) return send(res, 200, { code: 1200, status: 'TRANSACTION_EXIST' });
    const item = { ...body, status: 'PENDING', transaction_id: `CT${token().slice(0, 10)}`, notify_token: token() };
    transfers.set(body.merchant_transaction_id, item);
    setTimeout(() => {
      item.status = 'SUCCESS';
      notify(item);
    }, 1000);
    return send(res, 200, { code: 200, status: 'PENDING', transaction_id: item.transaction_id, notify_token: item.notify_token, merchant_transaction_id: body.merchant_transaction_id, amount: Number(body.amount), fee_amount: 0 });
  }

  if (req.method === 'GET' && a === 'v1' && b === 'transfer' && c) {
    const item = transfers.get(c);
    return item ? send(res, 200, { code: 200, status: item.status, transaction_id: item.transaction_id }) : send(res, 404, { code: 404 });
  }

  send(res, 404, { code: 404 });
}).listen(PORT, () => console.log(`Fake CinetPay listening on ${BASE}`));
