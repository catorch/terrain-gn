import { z } from 'zod';

const optional = z.preprocess((value) => (value === '' ? undefined : value), z.string().optional());

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().default(4100),
    DATABASE_URL: z.string().min(1),
    DATABASE_SSL: z.stringbool().default(false),
    JWT_SECRET: z.string().min(32),
    ADMIN_API_KEY: z.string().min(16),
    PUBLIC_API_URL: z.url().default('http://localhost:4100'),
    TWILIO_ACCOUNT_SID: optional,
    TWILIO_AUTH_TOKEN: optional,
    TWILIO_VERIFY_SID: optional,
    S3_ENDPOINT: optional,
    S3_REGION: z.string().default('us-east-1'),
    S3_BUCKET: z.string().default('terrain-docs'),
    S3_ACCESS_KEY_ID: optional,
    S3_SECRET_ACCESS_KEY: optional,
    S3_FORCE_PATH_STYLE: z.stringbool().default(false),
    CINETPAY_BASE_URL: z.url().default('https://api.cinetpay.net'),
    CINETPAY_API_KEY: optional,
    CINETPAY_API_PASSWORD: optional,
    // Lower of CinetPay's collection (2.5M) and transfer (1.5M) ceilings, so every deposit can also be paid out.
    CINETPAY_MAX_AMOUNT_GNF: z.coerce.number().int().positive().default(1_500_000),
    PLATFORM_FEE_BPS: z.coerce.number().int().min(0).max(10_000).default(300),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV !== 'production') return;
    if (!env.TWILIO_ACCOUNT_SID || !env.TWILIO_AUTH_TOKEN || !env.TWILIO_VERIFY_SID) {
      ctx.addIssue({ code: 'custom', path: ['TWILIO_VERIFY_SID'], message: 'Twilio Verify is required in production' });
    }
    if (!env.S3_ACCESS_KEY_ID || !env.S3_SECRET_ACCESS_KEY) {
      ctx.addIssue({ code: 'custom', path: ['S3_ACCESS_KEY_ID'], message: 'S3 credentials are required in production' });
    }
  });

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv) {
  return schema.parse(env);
}

export const config = loadConfig(process.env);

export const cinetpayConfigured = Boolean(config.CINETPAY_API_KEY && config.CINETPAY_API_PASSWORD);

export const twilioConfigured = Boolean(config.TWILIO_ACCOUNT_SID && config.TWILIO_AUTH_TOKEN && config.TWILIO_VERIFY_SID);
