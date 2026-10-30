import pg from 'pg';
import { migrate } from '../src/migrate.js';

// Recreates terrain_test from the migrations so every run starts from the real schema.
export default async function setup() {
  const url = new URL(process.env.TEST_DATABASE_URL ?? 'postgresql://terrain:terrain@localhost:5435/terrain_test');
  const name = url.pathname.slice(1);
  const admin = new pg.Client({ connectionString: Object.assign(new URL(url), { pathname: '/postgres' }).toString() });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${name}`);
  await admin.end();
  await migrate(url.toString());
}
