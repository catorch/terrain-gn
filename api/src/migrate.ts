import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import pg from 'pg';

const defaultDirectory = process.env.MIGRATIONS_DIR ?? path.resolve(import.meta.dirname, '../../sql');

export async function migrate(databaseUrl: string, directory = defaultDirectory) {
  const pool = new pg.Pool({ connectionString: databaseUrl, max: 1, application_name: 'terrain-gn-migrator' });
  const files = (await readdir(directory)).filter((file) => /^\d+.*\.sql$/.test(file)).sort();
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock(hashtext($1))', ['terrain-gn:schema-migrations']);
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      filename text PRIMARY KEY,
      checksum_sha256 text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);
    for (const filename of files) {
      const sql = await readFile(path.join(directory, filename), 'utf8');
      const checksum = createHash('sha256').update(sql).digest('hex');
      const prior = await client.query<{ checksum_sha256: string }>('SELECT checksum_sha256 FROM schema_migrations WHERE filename = $1', [filename]);
      if (prior.rows[0]) {
        if (prior.rows[0].checksum_sha256 !== checksum) throw new Error(`Applied migration was modified: ${filename}`);
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (filename, checksum_sha256) VALUES ($1, $2)', [filename, checksum]);
        await client.query('COMMIT');
        console.log(`Applied ${filename}`);
      } catch (error) {
        await client.query('ROLLBACK');
        throw new Error(`Migration ${filename} failed: ${(error as Error).message}`, { cause: error });
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock(hashtext($1))', ['terrain-gn:schema-migrations']).catch(() => undefined);
    client.release();
    await pool.end();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error('DATABASE_URL is required to run migrations');
  migrate(databaseUrl).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
