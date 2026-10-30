import { createHash, timingSafeEqual } from 'node:crypto';
import { Body, CanActivate, Controller, ExecutionContext, Get, HttpCode, Inject, Injectable, Param, ParseIntPipe, Post, Req, UseGuards } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import type { Request } from 'express';
import { z } from 'zod';
import { config } from './config.js';
import { audit, DatabaseService } from './db.js';
import { ApiError } from './errors.js';
import { StorageService } from './storage.service.js';

export type Staff = { email: string; role: 'agent' | 'admin' };
type StaffRequest = Request & { staff?: Staff };

const digest = (value: string) => createHash('sha256').update(value).digest();
const adminKeyDigest = digest(config.ADMIN_API_KEY);

/**
 * Retool calls the API with one shared key and names the signed-in Retool user in x-actor-email.
 * Only an active staff row turns that email into a role, so a leaked key alone cannot act.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<StaffRequest>();
    const presented = (request.headers.authorization ?? '').replace(/^Bearer /, '');
    if (!timingSafeEqual(digest(presented), adminKeyDigest)) throw new ApiError(401, 'ADMIN_KEY_INVALID');
    const email = String(request.headers['x-actor-email'] ?? '').trim().toLowerCase();
    const { rows } = await this.db.query<Staff>('SELECT email, role FROM staff WHERE email = $1 AND active', [email]);
    if (!rows[0]) throw new ApiError(403, 'STAFF_UNKNOWN');
    request.staff = rows[0];
    return true;
  }
}

export function requireAdmin(staff: Staff) {
  if (staff.role !== 'admin') throw new ApiError(403, 'ADMIN_ONLY');
}

const verificationSchema = z.object({ verified: z.boolean(), note: z.string().trim().max(1000).optional() });
const rejectSchema = z.object({ reason: z.string().trim().min(3).max(1000) });
// The agent confirms the wallet they actually looked at, so a change made while they were checking is not approved by accident.
const payoutVerificationSchema = z.object({ verified: z.boolean(), payoutPhone: z.string().regex(/^\+224\d{9}$/) });

@Controller('admin')
@UseGuards(AdminGuard)
@SkipThrottle()
export class AdminController {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(StorageService) private readonly storage: StorageService,
  ) {}

  /** The Retool badge toggle (R4.1, R4.2). Reserved and sold parcels have money attached and stay verified. */
  @Post('parcels/:id/verification')
  @HttpCode(200)
  setVerification(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number, @Body() body: unknown) {
    const { verified, note } = verificationSchema.parse(body);
    const staff = request.staff!;
    return this.db.transaction(async (client) => {
      const { rows } = await client.query<{ status: string }>('SELECT status FROM parcels WHERE id = $1 FOR UPDATE', [id]);
      const status = rows[0]?.status;
      if (!status) throw new ApiError(404, 'PARCEL_NOT_FOUND');
      const target = verified ? 'verified' : 'pending_verification';
      if (status === target) return { id, status, verified };
      if (status !== (verified ? 'pending_verification' : 'verified')) throw new ApiError(409, 'INVALID_STATUS', { status });
      await client.query(
        verified
          ? "UPDATE parcels SET status = 'verified', verified_by = $2, verified_at = now() WHERE id = $1"
          : "UPDATE parcels SET status = 'pending_verification', verified_by = NULL, verified_at = NULL WHERE id = $1 AND $2::text IS NOT NULL",
        [id, staff.email],
      );
      await audit(client, `staff:${staff.email}`, verified ? 'parcel.verified' : 'parcel.unverified', 'parcel', id, { note });
      return { id, status: target, verified };
    });
  }

  @Post('parcels/:id/reject')
  @HttpCode(200)
  reject(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number, @Body() body: unknown) {
    const { reason } = rejectSchema.parse(body);
    const staff = request.staff!;
    return this.db.transaction(async (client) => {
      const { rows } = await client.query(
        `UPDATE parcels SET status = 'rejected', rejection_reason = $2, verified_by = NULL, verified_at = NULL
         WHERE id = $1 AND status IN ('pending_verification', 'verified') RETURNING id`,
        [id, reason],
      );
      if (!rows[0]) throw new ApiError(409, 'INVALID_STATUS');
      await audit(client, `staff:${staff.email}`, 'parcel.rejected', 'parcel', id, { reason });
      return { id, status: 'rejected' };
    });
  }

  @Get('parcels/:id/documents')
  async documents(@Param('id', ParseIntPipe) id: number) {
    const { rows } = await this.db.query<{ id: number; kind: string; contentType: string; s3Key: string; uploadedAt: Date | null }>(
      'SELECT id, kind, content_type AS "contentType", s3_key AS "s3Key", uploaded_at AS "uploadedAt" FROM documents WHERE parcel_id = $1 ORDER BY id',
      [id],
    );
    return { items: await Promise.all(rows.map(async ({ s3Key, ...row }) => ({ ...row, url: row.uploadedAt ? await this.storage.presignGet(s3Key) : null }))) };
  }

  @Post('users/:id/payout-verification')
  @HttpCode(200)
  verifyPayout(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number, @Body() body: unknown) {
    const { verified, payoutPhone } = payoutVerificationSchema.parse(body);
    const staff = request.staff!;
    return this.db.transaction(async (client) => {
      const { rows } = await client.query<{ payoutMethod: string }>(
        'UPDATE users SET payout_verified = $2 WHERE id = $1 AND payout_phone = $3 RETURNING payout_method AS "payoutMethod"',
        [id, verified, payoutPhone],
      );
      if (!rows[0]) throw new ApiError(409, 'PAYOUT_WALLET_CHANGED');
      await audit(client, `staff:${staff.email}`, verified ? 'user.payout_verified' : 'user.payout_unverified', 'user', id, { payoutPhone, payoutMethod: rows[0].payoutMethod });
      return { id, payoutPhone, payoutVerified: verified };
    });
  }
}
