import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { resetDatabase } from '../test/helpers.js';
import { AuthService } from './auth.service.js';
import { loadConfig } from './config.js';
import { DatabaseService } from './db.js';

const db = new DatabaseService();
const auth = new AuthService(db);

beforeEach(() => resetDatabase(db.pool));
afterAll(() => db.onModuleDestroy());

describe('auth', () => {
  it('refuses to boot production without Twilio Verify', () => {
    expect(() => loadConfig({ ...process.env, NODE_ENV: 'production' })).toThrow(/Twilio Verify is required/);
  });

  it('creates the user on first OTP and returns working tokens', async () => {
    const session = await auth.verifyOtp('+224620000001', '000000');
    expect(session.user).toMatchObject({ phone: '+224620000001', locale: 'fr', payoutVerified: false });
    expect(await auth.verifyAccessToken(session.accessToken)).toBe(session.user.id);
    const again = await auth.verifyOtp('+224620000001', '000000');
    expect(again.user.id).toBe(session.user.id);
  });

  it('rejects a wrong code and a forged token', async () => {
    await expect(auth.verifyOtp('+224620000001', '123456')).rejects.toMatchObject({ response: { code: 'OTP_INVALID' } });
    await expect(auth.verifyAccessToken('not-a-jwt')).rejects.toMatchObject({ response: { code: 'TOKEN_INVALID' } });
  });

  it('rotates refresh tokens and revokes everything when a rotated token is replayed', async () => {
    const first = await auth.verifyOtp('+224620000001', '000000');
    const second = await auth.refresh(first.refreshToken);
    expect(second.refreshToken).not.toBe(first.refreshToken);
    await expect(auth.refresh(first.refreshToken)).rejects.toMatchObject({ response: { code: 'REFRESH_INVALID' } });
    await expect(auth.refresh(second.refreshToken)).rejects.toMatchObject({ response: { code: 'REFRESH_INVALID' } });
    const { rows } = await db.query("SELECT count(*)::int AS n FROM audit_events WHERE action = 'auth.refresh_reuse'");
    expect(rows[0]!.n).toBe(1);
  });

  it('logs out the whole token family', async () => {
    const session = await auth.verifyOtp('+224620000001', '000000');
    const rotated = await auth.refresh(session.refreshToken);
    await auth.logout(rotated.refreshToken);
    await expect(auth.refresh(rotated.refreshToken)).rejects.toMatchObject({ response: { code: 'REFRESH_INVALID' } });
  });

  it('resets wallet verification when the payout wallet changes', async () => {
    const { user } = await auth.verifyOtp('+224620000001', '000000');
    await auth.updateMe(user.id, { payout: { phone: '+224620000009', method: 'OM_GN' } });
    await db.query('UPDATE users SET payout_verified = true WHERE id = $1', [user.id]);
    const unchanged = await auth.updateMe(user.id, { name: 'Mariama', payout: { phone: '+224620000009', method: 'OM_GN' } });
    expect(unchanged).toMatchObject({ name: 'Mariama', payoutVerified: true });
    const changed = await auth.updateMe(user.id, { payout: { phone: '+224660000009', method: 'MTN_GN' } });
    expect(changed).toMatchObject({ payoutPhone: '+224660000009', payoutMethod: 'MTN_GN', payoutVerified: false });
    const { rows } = await db.query("SELECT count(*)::int AS n FROM audit_events WHERE action = 'user.payout_changed'");
    expect(rows[0]!.n).toBe(2);
  });
});
