import pg from 'pg';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { createUser, polygonGeoJson, rect, resetDatabase, type Corner } from '../test/helpers.js';

// These tests hit the database directly: the overlap rules must hold even for writes that bypass the API (R2.11).
const db = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 4 });
let owner: number;

beforeEach(async () => {
  await resetDatabase(db);
  owner = await createUser(db);
});
afterAll(() => db.end());

function insert(corners: Corner[], client: Pick<pg.PoolClient, 'query'> = db, titleRef: string | null = null) {
  return client.query<{ id: number; code: string; area_m2: number }>(
    `INSERT INTO parcels (owner_id, region, prefecture, locality, title, price_gnf, title_ref, boundary)
     VALUES ($1, 'conakry', 'Ratoma', 'Kipé', 'Terrain test', 150000000, $2, ST_SetSRID(ST_GeomFromGeoJSON($3), 4326))
     RETURNING id, code, area_m2`,
    [owner, titleRef, polygonGeoJson(corners)],
  );
}

async function overlapError(corners: Corner[]) {
  const error = await insert(corners).then(
    () => null,
    (caught: pg.DatabaseError) => caught,
  );
  expect(error?.code).toBe('23P01');
  return JSON.parse(error!.detail!) as Array<{ code: string; overlapM2: number; overlapRatio: number }>;
}

describe('parcel overlap engine', () => {
  it('stores a valid parcel with its geodesic area and plot code', async () => {
    const { rows } = await insert(rect(0, 0, 20, 25));
    expect(rows[0]!.code).toBe('TGN-000001');
    expect(rows[0]!.area_m2).toBeGreaterThan(495);
    expect(rows[0]!.area_m2).toBeLessThan(505);
  });

  it('rejects an identical boundary', async () => {
    await insert(rect(0, 0, 20, 25));
    const conflicts = await overlapError(rect(0, 0, 20, 25));
    expect(conflicts).toEqual([expect.objectContaining({ code: 'TGN-000001', overlapRatio: 1 })]);
  });

  it('rejects a small parcel placed inside an existing one', async () => {
    await insert(rect(0, 0, 100, 100));
    const [conflict] = await overlapError(rect(40, 40, 10, 10));
    expect(conflict!.overlapRatio).toBe(1);
  });

  it('rejects a large parcel that swallows an existing one', async () => {
    await insert(rect(40, 40, 10, 10));
    const [conflict] = await overlapError(rect(0, 0, 100, 100));
    expect(conflict!.overlapRatio).toBe(1);
  });

  it('rejects a partial overlap at or above 10% of the smaller parcel', async () => {
    await insert(rect(0, 0, 20, 25));
    const [conflict] = await overlapError(rect(17, 0, 20, 25)); // 3 m strip = 15%
    expect(conflict!.overlapM2).toBeGreaterThan(70);
    expect(conflict!.overlapRatio).toBeCloseTo(0.15, 2);
  });

  it('accepts a neighbour that only shares an edge', async () => {
    await insert(rect(0, 0, 20, 25));
    await expect(insert(rect(20, 0, 20, 25))).resolves.toBeTruthy();
  });

  it('accepts a GPS sliver below 10% and reports it as a soft conflict', async () => {
    const first = await insert(rect(0, 0, 20, 25));
    const second = await insert(rect(19, 0, 20, 25)); // 1 m strip = 5%
    const { rows } = await db.query('SELECT code, overlap_ratio FROM parcel_conflicts((SELECT boundary FROM parcels WHERE id = $1), $1)', [second.rows[0]!.id]);
    expect(rows).toEqual([{ code: first.rows[0]!.code, overlap_ratio: expect.closeTo(0.05, 2) }]);
  });

  it('ignores rejected and withdrawn claims', async () => {
    const { rows } = await insert(rect(0, 0, 20, 25));
    await db.query("UPDATE parcels SET status = 'rejected' WHERE id = $1", [rows[0]!.id]);
    await expect(insert(rect(0, 0, 20, 25))).resolves.toBeTruthy();
  });

  it('re-checks a rejected parcel that is reopened', async () => {
    const { rows } = await insert(rect(0, 0, 20, 25));
    await db.query("UPDATE parcels SET status = 'rejected' WHERE id = $1", [rows[0]!.id]);
    await insert(rect(0, 0, 20, 25));
    await expect(db.query("UPDATE parcels SET status = 'pending_verification' WHERE id = $1", [rows[0]!.id])).rejects.toMatchObject({ code: '23P01' });
  });

  it('rejects a self-intersecting bow-tie with the PostGIS reason', async () => {
    const [a, b, c, d] = rect(0, 0, 20, 25);
    const bowtie = [a!, c!, b!, d!];
    await expect(insert(bowtie)).rejects.toMatchObject({ code: '23514', constraint: 'parcels_boundary_ok' });
    const { rows } = await db.query('SELECT parcel_boundary_problem(g) AS problem, ST_IsValidReason(g) AS reason FROM ST_SetSRID(ST_GeomFromGeoJSON($1), 4326) g', [polygonGeoJson(bowtie)]);
    expect(rows[0]).toEqual({ problem: 'INVALID_GEOMETRY', reason: expect.stringContaining('Self-intersection') });
  });

  it('rejects boundaries outside Guinea and outside the area limits', async () => {
    const problem = async (geojson: string) =>
      (await db.query('SELECT parcel_boundary_problem(ST_SetSRID(ST_GeomFromGeoJSON($1), 4326)) AS p', [geojson])).rows[0].p;
    const dakar: Corner[] = [[-17.45, 14.7], [-17.449, 14.7], [-17.449, 14.701], [-17.45, 14.701]];
    expect(await problem(polygonGeoJson(dakar))).toBe('OUTSIDE_GUINEA');
    expect(await problem(polygonGeoJson(rect(0, 0, 5, 5)))).toBe('AREA_OUT_OF_RANGE');
    expect(await problem(polygonGeoJson(rect(0, 0, 3000, 2000)))).toBe('AREA_OUT_OF_RANGE');
    expect(await problem(polygonGeoJson(rect(0, 0, 20, 25)))).toBeNull();
  });

  it('transforms UTM zone 28N survey coordinates into the same footprint', async () => {
    const { rows } = await db.query<{ corners: Corner[] }>(
      `SELECT array_agg(ARRAY[ST_X(p.geom), ST_Y(p.geom)] ORDER BY p.path) AS corners
       FROM ST_DumpPoints(ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON($1), 4326), 32628)) p`,
      [polygonGeoJson(rect(0, 0, 20, 25))],
    );
    const utm = rows[0]!.corners.slice(0, 4);
    expect(utm[0]![0]).toBeGreaterThan(100_000); // eastings, not degrees
    await insert(rect(0, 0, 20, 25));
    const utmInsert = db.query(
      `INSERT INTO parcels (owner_id, region, prefecture, locality, title, price_gnf, boundary)
       VALUES ($1, 'conakry', 'Ratoma', 'Kipé', 'Terrain UTM', 1, ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON($2), 32628), 4326))`,
      [owner, polygonGeoJson(utm)],
    );
    await expect(utmInsert).rejects.toMatchObject({ code: '23P01' });
  });

  it('rejects a duplicate title reference regardless of case and spacing', async () => {
    await insert(rect(0, 0, 20, 25), db, 'TF 1234/CKY');
    await expect(insert(rect(100, 0, 20, 25), db, 'tf1234/cky')).rejects.toMatchObject({ code: '23505', constraint: 'parcels_title_ref_active' });
  });

  it('lets exactly one of two simultaneous overlapping submissions win', async () => {
    const a = await db.connect();
    const b = await db.connect();
    try {
      await a.query('BEGIN');
      await b.query('BEGIN');
      await insert(rect(0, 0, 20, 25), a);
      const blocked = insert(rect(5, 5, 20, 25), b).then(
        () => 'inserted',
        (error: pg.DatabaseError) => error.code,
      );
      await new Promise((resolve) => setTimeout(resolve, 200));
      await a.query('COMMIT');
      expect(await blocked).toBe('23P01');
      await b.query('ROLLBACK');
    } finally {
      a.release();
      b.release();
    }
    const { rows } = await db.query('SELECT count(*)::int AS n FROM parcels');
    expect(rows[0].n).toBe(1);
  });

  it('keeps audit events append-only', async () => {
    await db.query("INSERT INTO audit_events (actor, action, entity, entity_id) VALUES ('test', 'x', 'parcel', 1)");
    await expect(db.query('DELETE FROM audit_events')).rejects.toThrow(/append-only/);
  });
});
