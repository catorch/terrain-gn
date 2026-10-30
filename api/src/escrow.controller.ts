import { Body, Controller, Get, Header, Headers, HttpCode, Inject, Param, ParseIntPipe, Post, Req, UseGuards } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import type { Request } from 'express';
import { z } from 'zod';
import { AdminGuard, requireAdmin, type Staff } from './admin.controller.js';
import { AuthGuard, type AuthedRequest } from './auth.guard.js';
import { EscrowService } from './escrow.service.js';

const idempotencyKeySchema = z.string().min(8).max(100);
type StaffRequest = Request & { staff?: Staff };

@Controller()
export class EscrowController {
  constructor(@Inject(EscrowService) private readonly escrow: EscrowService) {}

  @Post('parcels/:id/reservations')
  @UseGuards(AuthGuard)
  reserve(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number, @Headers('idempotency-key') idempotencyKey?: string) {
    return this.escrow.reserve(request.userId!, id, idempotencyKeySchema.parse(idempotencyKey));
  }

  @Get('reservations/:id')
  @UseGuards(AuthGuard)
  get(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number) {
    return this.escrow.get(request.userId!, id);
  }

  @Get('me/reservations')
  @UseGuards(AuthGuard)
  mine(@Req() request: AuthedRequest) {
    return this.escrow.mine(request.userId!);
  }

  @Post('webhooks/cinetpay/payment')
  @HttpCode(200)
  @SkipThrottle()
  paymentWebhook(@Body() body: Record<string, unknown>) {
    return this.escrow.paymentWebhook(body ?? {});
  }

  @Post('webhooks/cinetpay/transfer')
  @HttpCode(200)
  @SkipThrottle()
  transferWebhook(@Body() body: Record<string, unknown>) {
    return this.escrow.transferWebhook(body ?? {});
  }

  /** Where CinetPay sends the buyer after paying; the app polls the reservation when it comes back to the foreground. */
  @Get('payments/return')
  @Header('content-type', 'text/html; charset=utf-8')
  returnPage() {
    return '<!doctype html><meta name="viewport" content="width=device-width"><title>Terrain GN</title><body style="font-family:sans-serif;text-align:center;padding:48px 16px"><h2>Paiement reçu · Payment received</h2><p>Retournez dans l\'application Terrain GN.<br>Return to the Terrain GN app.</p></body>';
  }
}

@Controller('admin')
@UseGuards(AdminGuard)
@SkipThrottle()
export class AdminEscrowController {
  constructor(@Inject(EscrowService) private readonly escrow: EscrowService) {}

  @Post('reservations/:id/release')
  @HttpCode(200)
  release(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number) {
    requireAdmin(request.staff!);
    return this.escrow.release(request.staff!, id);
  }

  @Post('reservations/:id/refund')
  @HttpCode(200)
  refund(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number) {
    requireAdmin(request.staff!);
    return this.escrow.refund(request.staff!, id);
  }

  @Post('payouts/:id/reconcile')
  @HttpCode(200)
  reconcile(@Req() request: StaffRequest, @Param('id', ParseIntPipe) id: number) {
    requireAdmin(request.staff!);
    return this.escrow.reconcilePayout(id);
  }
}
