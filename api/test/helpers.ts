import pg from 'pg';

export type Corner = [number, number];

// Conakry, Ratoma. Offsets below are in metres east/north of this point.
const BASE_LON = -13.6;
const BASE_LAT = 9.6;
const M_PER_DEG_LAT = 110_610;
const M_PER_DEG_LON = 111_320 * Math.cos((BASE_LAT * Math.PI) / 180);

export function point(eastM: number, northM: number): Corner {
  return [BASE_LON + eastM / M_PER_DEG_LON, BASE_LAT + northM / M_PER_DEG_LAT];
}

/** Axis-aligned rectangle `w` × `h` metres whose south-west corner is `x`, `y` metres from the base point. */
export function rect(x: number, y: number, w: number, h: number): Corner[] {
  return [point(x, y), point(x + w, y), point(x + w, y + h), point(x, y + h)];
}

export function polygonGeoJson(corners: Corner[]) {
  return JSON.stringify({ type: 'Polygon', coordinates: [[...corners, corners[0]]] });
}

export async function resetDatabase(db: pg.Pool) {
  await db.query('TRUNCATE payment_events, payouts, reservations, parcels, users, staff, documents, contact_leads, overlap_attempts, audit_events, refresh_tokens RESTART IDENTITY CASCADE');
}

export async function createUser(db: pg.Pool, phone = `+22462${Math.floor(1_000_000 + Math.random() * 8_999_999)}`) {
  const { rows } = await db.query<{ id: number }>('INSERT INTO users (phone) VALUES ($1) RETURNING id', [phone]);
  return rows[0]!.id;
}
