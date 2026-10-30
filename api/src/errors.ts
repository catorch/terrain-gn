import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';
import { ZodError } from 'zod';

/** Every error the API sends carries a stable `code` the mobile client localizes. */
export class ApiError extends HttpException {
  constructor(status: number, code: string, extra: Record<string, unknown> = {}) {
    super({ code, ...extra }, status);
  }
}

const STATUS_CODES: Record<number, string> = { 400: 'BAD_REQUEST', 401: 'UNAUTHORIZED', 403: 'FORBIDDEN', 404: 'NOT_FOUND', 429: 'RATE_LIMITED' };

/** Gives Nest's own exceptions (throttler, ParseIntPipe, unknown routes) the same `code` shape as ApiError. */
@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  catch(error: HttpException, host: ArgumentsHost) {
    const status = error.getStatus();
    const body = error.getResponse();
    const response = host.switchToHttp().getResponse();
    if (typeof body === 'object' && 'code' in body) return response.status(status).json(body);
    response.status(status).json({ code: STATUS_CODES[status] ?? 'ERROR', message: error.message });
  }
}

@Catch(ZodError)
export class ZodExceptionFilter implements ExceptionFilter {
  catch(error: ZodError, host: ArgumentsHost) {
    host
      .switchToHttp()
      .getResponse()
      .status(400)
      .json({ code: 'VALIDATION_FAILED', issues: error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.message })) });
  }
}
