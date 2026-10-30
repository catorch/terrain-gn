import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { jwtVerify, SignJWT } from 'jose';
import { config, twilioConfigured } from './config.js';
import { audit, DatabaseService } from './db.js';
import { ApiError } from './errors.js';

const ACCESS_TTL_SECONDS = 15 * 60;
const REFRESH_TTL_DAYS = 30;
const DEV_OTP = '000000';
const secret = new TextEncoder().encode(config.JWT_SECRET);

const sha256 = (value: string) => createHash('sha256').update(value).digest();

export interface User {
  id: number;
  phone: string;
  name: string | null;
  locale: 'fr' | 'en';
  payoutPhone: string | null;
  payoutMethod: 'OM_GN' | 'MTN_GN' | null;
  payoutVerified: boolean;
}

const USER_COLUMNS = 'id, phone, name, locale, payout_phone AS "payoutPhone", payout_method AS "payoutMethod", payout_verified AS "payoutVerified"';

async function twilioVerify(path: 'Verifications' | 'VerificationCheck', form: Record<string, string>) {
  const credentials = Buffer.from(`${config.TWILIO_ACCOUNT_SID}:${config.TWILIO_AUTH_TOKEN}`).toString('base64');
  return fetch(`https://verify.twilio.com/v2/Services/${config.TWILIO_VERIFY_SID}/${path}`, {
    method: 'POST',
    headers: { authorization: `Basic ${credentials}`, 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form),
    signal: AbortSignal.timeout(10_000),
  });
}

@Injectable()
export class AuthService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async startOtp(phone: string, channel: 'sms' | 'whatsapp') {
    if (!twilioConfigured) return; // config.ts refuses to boot production without Twilio
    const response = await twilioVerify('Verifications', { To: phone, Channel: channel });
    if (!response.ok) throw new ApiError(400, 'OTP_SEND_FAILED');
  }

  async verifyOtp(phone: string, code: string) {
    if (!(await this.otpApproved(phone, code))) throw new ApiError(401, 'OTP_INVALID');
    const { rows } = await this.db.query<{ id: number }>(
      'INSERT INTO users (phone) VALUES ($1) ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone RETURNING id',
      [phone],
    );
    return this.issueTokens(rows[0]!.id, randomUUID());
  }

  private async otpApproved(phone: string, code: string) {
    if (!twilioConfigured) return code === DEV_OTP;
    const response = await twilioVerify('VerificationCheck', { To: phone, Code: code });
    if (response.status === 404) return false; // expired, already used, or never started
    if (!response.ok) throw new ApiError(502, 'OTP_PROVIDER_UNAVAILABLE');
    return ((await response.json()) as { status?: string }).status === 'approved';
  }

  async refresh(refreshToken: string) {
    const hash = sha256(refreshToken);
    const { rows } = await this.db.query<{ user_id: number; family: string }>(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now() RETURNING user_id, family',
      [hash],
    );
    if (rows[0]) return this.issueTokens(rows[0].user_id, rows[0].family);
    // A revoked token presented again means it leaked (or two clients raced); end every session for that user.
    const reused = await this.db.query<{ user_id: number }>(
      `UPDATE refresh_tokens SET revoked_at = now()
       WHERE user_id = (SELECT user_id FROM refresh_tokens WHERE token_hash = $1 AND revoked_at IS NOT NULL) AND revoked_at IS NULL
       RETURNING user_id`,
      [hash],
    );
    if (reused.rows[0]) await audit(this.db, `user:${reused.rows[0].user_id}`, 'auth.refresh_reuse', 'user', reused.rows[0].user_id);
    throw new ApiError(401, 'REFRESH_INVALID');
  }

  async logout(refreshToken: string) {
    await this.db.query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE family = (SELECT family FROM refresh_tokens WHERE token_hash = $1) AND revoked_at IS NULL',
      [sha256(refreshToken)],
    );
  }

  async verifyAccessToken(token: string) {
    try {
      const { payload } = await jwtVerify(token, secret, { algorithms: ['HS256'] });
      return Number(payload.sub);
    } catch {
      throw new ApiError(401, 'TOKEN_INVALID');
    }
  }

  private async issueTokens(userId: number, family: string) {
    const accessToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(String(userId))
      .setIssuedAt()
      .setExpirationTime(`${ACCESS_TTL_SECONDS}s`)
      .sign(secret);
    const refreshToken = randomBytes(32).toString('base64url');
    await this.db.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, family, expires_at) VALUES ($1, $2, $3, now() + make_interval(days => $4))`,
      [userId, sha256(refreshToken), family, REFRESH_TTL_DAYS],
    );
    return { accessToken, refreshToken, expiresIn: ACCESS_TTL_SECONDS, user: await this.me(userId) };
  }

  async me(userId: number) {
    const { rows } = await this.db.query<User>(
      `SELECT ${USER_COLUMNS} FROM users WHERE id = $1`,
      [userId],
    );
    if (!rows[0]) throw new ApiError(401, 'TOKEN_INVALID');
    return rows[0];
  }

  async updateMe(userId: number, patch: { name?: string; locale?: 'fr' | 'en'; payout?: { phone: string; method: 'OM_GN' | 'MTN_GN' } }) {
    return this.db.transaction(async (client) => {
      const { rows } = await client.query<User>(
        `UPDATE users SET name = COALESCE($2, name), locale = COALESCE($3, locale) WHERE id = $1
         RETURNING ${USER_COLUMNS}`,
        [userId, patch.name ?? null, patch.locale ?? null],
      );
      let user = rows[0]!;
      const payoutChanged = patch.payout && (patch.payout.phone !== user.payoutPhone || patch.payout.method !== user.payoutMethod);
      if (payoutChanged) {
        // A new wallet blocks releases until an agent confirms it (R7.10): account takeover must not redirect payouts.
        const updated = await client.query<User>(
          `UPDATE users SET payout_phone = $2, payout_method = $3, payout_verified = false WHERE id = $1
           RETURNING ${USER_COLUMNS}`,
          [userId, patch.payout!.phone, patch.payout!.method],
        );
        user = updated.rows[0]!;
        await audit(client, `user:${userId}`, 'user.payout_changed', 'user', userId, { phone: user.payoutPhone, method: user.payoutMethod });
      }
      return user;
    });
  }
}
