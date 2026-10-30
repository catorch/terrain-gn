import { Body, Controller, Get, HttpCode, Inject, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { AuthGuard, type AuthedRequest } from './auth.guard.js';
import { AuthService } from './auth.service.js';

export const phoneSchema = z.string().regex(/^\+[1-9]\d{7,14}$/, 'Phone must be in E.164 format, e.g. +224620000000');
const startSchema = z.object({ phone: phoneSchema, channel: z.enum(['sms', 'whatsapp']).default('sms') });
const verifySchema = z.object({ phone: phoneSchema, code: z.string().regex(/^\d{4,10}$/) });
const refreshSchema = z.object({ refreshToken: z.string().min(20).max(200) });
const meSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  locale: z.enum(['fr', 'en']).optional(),
  payout: z.object({ phone: z.string().regex(/^\+224\d{9}$/, 'Payout wallet must be a Guinean number'), method: z.enum(['OM_GN', 'MTN_GN']) }).optional(),
});

@Controller()
export class AuthController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}

  @Post('auth/otp/start')
  @HttpCode(202)
  @Throttle({ default: { limit: 3, ttl: 60_000 } })
  async start(@Body() body: unknown) {
    const input = startSchema.parse(body);
    await this.auth.startOtp(input.phone, input.channel);
    return { sent: true };
  }

  @Post('auth/otp/verify')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  verify(@Body() body: unknown) {
    const input = verifySchema.parse(body);
    return this.auth.verifyOtp(input.phone, input.code);
  }

  @Post('auth/refresh')
  @HttpCode(200)
  refresh(@Body() body: unknown) {
    return this.auth.refresh(refreshSchema.parse(body).refreshToken);
  }

  @Post('auth/logout')
  @HttpCode(204)
  async logout(@Body() body: unknown) {
    await this.auth.logout(refreshSchema.parse(body).refreshToken);
  }

  @Get('me')
  @UseGuards(AuthGuard)
  me(@Req() request: AuthedRequest) {
    return this.auth.me(request.userId!);
  }

  @Patch('me')
  @UseGuards(AuthGuard)
  updateMe(@Req() request: AuthedRequest, @Body() body: unknown) {
    return this.auth.updateMe(request.userId!, meSchema.parse(body));
  }
}
