import { defineConfig } from 'vitest/config';

const testDatabaseUrl = process.env.TEST_DATABASE_URL ?? 'postgresql://terrain:terrain@localhost:5435/terrain_test';

export default defineConfig({
  test: {
    globalSetup: './test/global-setup.ts',
    fileParallelism: false,
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: testDatabaseUrl,
      JWT_SECRET: 'test-secret-that-is-at-least-32-characters',
      ADMIN_API_KEY: 'test-admin-key-0123456789',
      S3_ENDPOINT: 'http://localhost:9190',
      S3_FORCE_PATH_STYLE: 'true',
      S3_ACCESS_KEY_ID: 'local',
      S3_SECRET_ACCESS_KEY: 'local',
    },
  },
});
