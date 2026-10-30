import { Controller, Get, Inject, Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { SkipThrottle, ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AdminController, AdminGuard } from './admin.controller.js';
import { AuthController } from './auth.controller.js';
import { AuthGuard, OptionalAuthGuard } from './auth.guard.js';
import { AuthService } from './auth.service.js';
import { CinetPayClient } from './cinetpay.js';
import { DatabaseService } from './db.js';
import { ApiError } from './errors.js';
import { AdminEscrowController, EscrowController } from './escrow.controller.js';
import { EscrowService } from './escrow.service.js';
import { ParcelsController } from './parcels.controller.js';
import { ParcelsService } from './parcels.service.js';
import { StorageService } from './storage.service.js';

@Controller()
@SkipThrottle()
class HealthController {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  @Get('health')
  health() {
    return { ok: true };
  }

  @Get('ready')
  async ready() {
    await this.db.query('SELECT 1').catch(() => {
      throw new ApiError(503, 'DATABASE_UNAVAILABLE');
    });
    return { ok: true };
  }
}

@Module({
  imports: [ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }])],
  controllers: [HealthController, AuthController, ParcelsController, AdminController, EscrowController, AdminEscrowController],
  providers: [
    DatabaseService,
    StorageService,
    AuthService,
    ParcelsService,
    EscrowService,
    { provide: CinetPayClient, useFactory: () => new CinetPayClient() },
    AuthGuard,
    OptionalAuthGuard,
    AdminGuard,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
