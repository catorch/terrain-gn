import { Injectable, OnModuleDestroy } from '@nestjs/common';
import pg, { type PoolClient, type QueryResult, type QueryResultRow } from 'pg';
import { config } from './config.js';

// bigint ids and integer GNF amounts stay far below 2^53.
pg.types.setTypeParser(pg.types.builtins.INT8, Number);

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  readonly pool = new pg.Pool({
    connectionString: config.DATABASE_URL,
    max: 12,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
    ssl: config.DATABASE_SSL ? { rejectUnauthorized: true } : undefined,
    application_name: 'terrain-gn-api',
  });

  query<T extends QueryResultRow = QueryResultRow>(text: string, values: unknown[] = []): Promise<QueryResult<T>> {
    return this.pool.query<T>(text, values);
  }

  async transaction<T>(work: (client: PoolClient) => Promise<T>) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const value = await work(client);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}

type Queryable = { query(text: string, values: unknown[]): Promise<unknown> };

export function audit(db: Queryable, actor: string, action: string, entity: string, entityId: number, data: Record<string, unknown> = {}) {
  return db.query('INSERT INTO audit_events (actor, action, entity, entity_id, data) VALUES ($1, $2, $3, $4, $5)', [actor, action, entity, entityId, data]);
}
