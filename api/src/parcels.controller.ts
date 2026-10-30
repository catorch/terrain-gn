import { Body, Controller, Get, Headers, HttpCode, Inject, Param, ParseIntPipe, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AuthGuard, OptionalAuthGuard, type AuthedRequest } from './auth.guard.js';
import { boundarySchema, createParcelSchema, ParcelsService, REGIONS, updateParcelSchema, uploadSchema } from './parcels.service.js';

const listSchema = z.object({ region: z.enum(REGIONS).optional(), cursor: z.coerce.number().int().positive().optional() });
const idempotencyKeySchema = z.string().min(8).max(100).optional();

@Controller()
export class ParcelsController {
  constructor(@Inject(ParcelsService) private readonly parcels: ParcelsService) {}

  @Get('parcels')
  list(@Query() query: unknown) {
    const { region, cursor } = listSchema.parse(query);
    return this.parcels.list(region, cursor);
  }

  @Post('parcels/check')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  check(@Body() body: unknown) {
    return this.parcels.check(boundarySchema.parse(body));
  }

  @Post('parcels')
  @UseGuards(AuthGuard)
  create(@Req() request: AuthedRequest, @Body() body: unknown, @Headers('idempotency-key') idempotencyKey?: string) {
    return this.parcels.create(request.userId!, createParcelSchema.parse(body), idempotencyKeySchema.parse(idempotencyKey));
  }

  @Get('me/parcels')
  @UseGuards(AuthGuard)
  mine(@Req() request: AuthedRequest) {
    return this.parcels.mine(request.userId!);
  }

  @Get('parcels/:id')
  @UseGuards(OptionalAuthGuard)
  detail(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number) {
    return this.parcels.detail(id, request.userId);
  }

  @Patch('parcels/:id')
  @UseGuards(AuthGuard)
  update(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number, @Body() body: unknown) {
    return this.parcels.update(request.userId!, id, updateParcelSchema.parse(body));
  }

  @Post('parcels/:id/withdraw')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  withdraw(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number) {
    return this.parcels.withdraw(request.userId!, id);
  }

  @Post('parcels/:id/contact')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  contact(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number) {
    return this.parcels.contact(request.userId!, id);
  }

  @Post('parcels/:id/documents')
  @UseGuards(AuthGuard)
  requestUpload(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number, @Body() body: unknown) {
    return this.parcels.requestUpload(request.userId!, id, uploadSchema.parse(body));
  }

  @Post('parcels/:id/documents/:documentId/complete')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  completeUpload(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number, @Param('documentId', ParseIntPipe) documentId: number) {
    return this.parcels.completeUpload(request.userId!, id, documentId);
  }

  @Get('parcels/:id/documents')
  @UseGuards(OptionalAuthGuard)
  documents(@Req() request: AuthedRequest, @Param('id', ParseIntPipe) id: number) {
    return this.parcels.documents(id, request.userId);
  }
}
