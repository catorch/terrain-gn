import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { NestFactory } from '@nestjs/core';
import compression from 'compression';
import type { NextFunction, Request, Response } from 'express';
import helmet from 'helmet';
import { AppModule } from './app.module.js';
import { config } from './config.js';
import { HttpExceptionFilter, ZodExceptionFilter } from './errors.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { logger: ['log', 'warn', 'error'], rawBody: true });
  app.setGlobalPrefix('v1');
  // Bearer tokens only, no cookies, so an open origin exposes nothing extra.
  app.enableCors({ allowedHeaders: ['content-type', 'authorization', 'idempotency-key', 'accept-language'] });
  app.use(helmet());
  app.use(compression());
  app.useGlobalFilters(new HttpExceptionFilter(), new ZodExceptionFilter());
  const express = app.getHttpAdapter().getInstance();
  express.disable('x-powered-by');
  express.set('trust proxy', 1);
  express.use((request: Request & { id?: string }, response: Response, next: NextFunction) => {
    const inbound = request.headers['x-request-id'];
    request.id = typeof inbound === 'string' && inbound.length <= 100 ? inbound : randomUUID();
    response.setHeader('x-request-id', request.id);
    next();
  });
  app.enableShutdownHooks();
  await app.listen(config.PORT, '0.0.0.0');
}

void bootstrap();
