import { CanActivate, ExecutionContext, Inject, Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from './auth.service.js';
import { ApiError } from './errors.js';

export type AuthedRequest = Request & { userId?: number };

function bearer(request: Request) {
  const header = request.headers.authorization;
  return header?.startsWith('Bearer ') ? header.slice(7) : undefined;
}

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthedRequest>();
    const token = bearer(request);
    if (!token) throw new ApiError(401, 'TOKEN_MISSING');
    request.userId = await this.auth.verifyAccessToken(token);
    return true;
  }
}

/** For public endpoints that show more to a signed-in owner. A bad token is treated as anonymous. */
@Injectable()
export class OptionalAuthGuard implements CanActivate {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthedRequest>();
    const token = bearer(request);
    if (token) request.userId = await this.auth.verifyAccessToken(token).catch(() => undefined);
    return true;
  }
}
