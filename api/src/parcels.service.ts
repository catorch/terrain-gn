import { randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import type { DatabaseError } from 'pg';
import { z } from 'zod';
import { audit, DatabaseService } from './db.js';
import { ApiError } from './errors.js';
import { StorageService } from './storage.service.js';
import { whatsappHandoff } from './whatsapp.js';

export const REGIONS = ['conakry', 'boke', 'kindia', 'mamou', 'labe', 'faranah', 'kankan', 'nzerekore'] as const;
const SRIDS = { 'EPSG:4326': 4326, 'EPSG:32628': 32628, 'EPSG:32629': 32629 } as const;
const PUBLIC_STATUSES = ['verified', 'reserved'];
const MAX_DOCUMENTS_PER_PARCEL = 20;
const singleLine = (min: number, max: number) => z.string().trim().min(min).max(max).regex(/^[^\r\n]+$/, 'Must be a single line');

export const boundarySchema = z
  .object({
    corners: z.array(z.tuple([z.number(), z.number()])).min(3).max(201),
    crs: z.enum(['EPSG:4326', 'EPSG:32628', 'EPSG:32629']).default('EPSG:4326'),
  })
  .refine((b) => b.crs !== 'EPSG:4326' || b.corners.every(([lon, lat]) => Math.abs(lon) <= 180 && Math.abs(lat) <= 90), {
    message: 'EPSG:4326 corners are [longitude, latitude]',
    path: ['corners'],
  });

export const createParcelSchema = z
  .object({
    boundary: boundarySchema,
    title: singleLine(3, 140),
    region: z.enum(REGIONS),
    prefecture: singleLine(2, 80),
    locality: singleLine(2, 120),
    priceGnf: z.number().int().positive().max(1e13),
    depositGnf: z.number().int().positive().optional(),
    titleRef: singleLine(1, 80).optional(),
  })
  .refine((p) => !p.depositGnf || p.depositGnf <= p.priceGnf, { message: 'Deposit cannot exceed the price', path: ['depositGnf'] });

export const updateParcelSchema = z.object({
  title: singleLine(3, 140).optional(),
  priceGnf: z.number().int().positive().max(1e13).optional(),
  depositGnf: z.number().int().positive().nullable().optional(),
});

export const uploadSchema = z.object({
  kind: z.enum(['title_deed', 'survey_plan', 'photo', 'id_card']),
  contentType: z.enum(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  sizeBytes: z.number().int().min(1).max(10 * 1024 * 1024),
});

type Boundary = z.infer<typeof boundarySchema>;
type Conflict = { code: string; overlapM2: number; overlapRatio: number; blocking?: boolean };

/** Closes the ring the way GeoJSON wants; the seller lists each borne once. */
function ringGeoJson(corners: Boundary['corners']) {
  const [first, last] = [corners[0]!, corners.at(-1)!];
  const open = first[0] === last[0] && first[1] === last[1] ? corners.slice(0, -1) : corners;
  if (open.length < 3) throw new ApiError(400, 'TOO_FEW_CORNERS');
  return JSON.stringify({ type: 'Polygon', coordinates: [[...open, open[0]]] });
}

const CANDIDATE = 'ST_Transform(ST_SetSRID(ST_GeomFromGeoJSON($1), $2::int), 4326)';

const LIST_COLUMNS = `p.id, p.code, p.status, p.title, p.region, p.prefecture, p.locality, p.price_gnf AS "priceGnf",
  p.deposit_gnf AS "depositGnf", round(p.area_m2) AS "areaM2", p.verified_at AS "verifiedAt",
  (SELECT d.s3_key FROM documents d WHERE d.parcel_id = p.id AND d.kind = 'photo' AND d.uploaded_at IS NOT NULL ORDER BY d.id LIMIT 1) AS "coverKey"`;

type ListRow = { id: number; code: string; status: string; verifiedAt: Date | null; coverKey: string | null } & Record<string, unknown>;

@Injectable()
export class ParcelsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(StorageService) private readonly storage: StorageService,
  ) {}

  /** Dry run (R2.8): the same SQL rules as the insert, without storing anything. */
  async check(boundary: Boundary) {
    const geojson = ringGeoJson(boundary.corners);
    const row = await this.db
      .query<{ problem: string | null; reason: string | null; areaM2: number | null; conflicts: Conflict[] }>(
        `SELECT s.problem,
                CASE WHEN s.problem = 'INVALID_GEOMETRY' THEN ST_IsValidReason(s.g) END AS reason,
                CASE WHEN s.problem IS NULL OR s.problem = 'AREA_OUT_OF_RANGE' THEN round(ST_Area(s.g::geography)) END AS "areaM2",
                CASE WHEN s.problem IS NULL THEN (
                  SELECT coalesce(json_agg(json_build_object('code', c.code, 'overlapM2', round(c.overlap_m2::numeric, 1),
                    'overlapRatio', round(c.overlap_ratio::numeric, 3), 'blocking', c.overlap_ratio >= overlap_hard_ratio())), '[]')
                  FROM parcel_conflicts(s.g) c)
                ELSE '[]' END AS conflicts
         FROM (SELECT g, parcel_boundary_problem(g) AS problem FROM ${CANDIDATE} g) s`,
        [geojson, SRIDS[boundary.crs]],
      )
      .then(
        (result) => result.rows[0]!,
        (error: DatabaseError) => {
          if (error.code === 'XX000' || error.code === '22023') return { problem: 'INVALID_GEOMETRY', reason: error.message, areaM2: null, conflicts: [] };
          throw error;
        },
      );
    return { ok: !row.problem && !row.conflicts.some((c) => c.blocking), ...row };
  }

  async create(ownerId: number, input: z.infer<typeof createParcelSchema>, idempotencyKey?: string): Promise<Awaited<ReturnType<ParcelsService['detail']>>> {
    if (idempotencyKey) {
      const prior = await this.db.query<{ id: number }>('SELECT id FROM parcels WHERE owner_id = $1 AND idempotency_key = $2', [ownerId, idempotencyKey]);
      if (prior.rows[0]) return this.detail(prior.rows[0].id, ownerId);
    }
    const check = await this.check(input.boundary);
    if (check.problem) throw new ApiError(422, 'BOUNDARY_INVALID', { problem: check.problem, reason: check.reason, areaM2: check.areaM2 });
    const geojson = ringGeoJson(input.boundary.corners);
    const srid = SRIDS[input.boundary.crs];
    try {
      const { rows } = await this.db.query<{ id: number }>(
        `INSERT INTO parcels (boundary, owner_id, region, prefecture, locality, title, price_gnf, deposit_gnf, title_ref, idempotency_key)
         VALUES (${CANDIDATE}, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id`,
        [geojson, srid, ownerId, input.region, input.prefecture, input.locality, input.title, input.priceGnf, input.depositGnf ?? null, input.titleRef ?? null, idempotencyKey ?? null],
      );
      await audit(this.db, `user:${ownerId}`, 'parcel.submitted', 'parcel', rows[0]!.id);
      return this.detail(rows[0]!.id, ownerId);
    } catch (error) {
      const dbError = error as DatabaseError;
      if (dbError.code === '23P01') {
        const conflicts = JSON.parse(dbError.detail ?? '[]') as Conflict[];
        // Someone tried to claim land already on file: keep the attempt for the fraud page in Retool (R2.5).
        await this.db.query(`INSERT INTO overlap_attempts (candidate, conflicts, user_id) VALUES (${CANDIDATE}, $3, $4)`, [geojson, srid, JSON.stringify(conflicts), ownerId]);
        throw new ApiError(409, 'PARCEL_OVERLAP', { conflicts });
      }
      if (dbError.code === '23505' && dbError.constraint === 'parcels_title_ref_active') throw new ApiError(409, 'DUPLICATE_TITLE_REF');
      if (dbError.code === '23505' && dbError.constraint === 'parcels_idempotency') return this.create(ownerId, input, idempotencyKey);
      throw error;
    }
  }

  async list(region: string | undefined, cursor: number | undefined) {
    const { rows } = await this.db.query<ListRow>(
      `SELECT ${LIST_COLUMNS} FROM parcels p
       WHERE p.status = ANY($1) AND ($2::text IS NULL OR p.region = $2) AND ($3::bigint IS NULL OR p.id < $3)
       ORDER BY p.id DESC LIMIT 21`,
      [PUBLIC_STATUSES, region ?? null, cursor ?? null],
    );
    const page = rows.slice(0, 20);
    return { items: await Promise.all(page.map((row) => this.listItem(row))), nextCursor: rows.length > 20 ? page.at(-1)!.id : null };
  }

  async mine(ownerId: number) {
    const { rows } = await this.db.query<ListRow>(`SELECT ${LIST_COLUMNS} FROM parcels p WHERE p.owner_id = $1 ORDER BY p.id DESC`, [ownerId]);
    return { items: await Promise.all(rows.map((row) => this.listItem(row))) };
  }

  private async listItem({ coverKey, ...row }: ListRow) {
    return { ...row, verified: row.verifiedAt !== null, coverUrl: coverKey ? await this.storage.presignGet(coverKey) : null };
  }

  async detail(id: number, viewerId?: number) {
    const { rows } = await this.db.query(
      `SELECT ${LIST_COLUMNS}, p.owner_id AS "ownerId", p.title_ref AS "titleRef", p.rejection_reason AS "rejectionReason",
              p.created_at AS "createdAt", ST_AsGeoJSON(p.boundary, 7)::json AS boundary,
              json_build_array(ST_X(ST_Centroid(p.boundary)), ST_Y(ST_Centroid(p.boundary))) AS centroid,
              (SELECT coalesce(json_agg(d.s3_key ORDER BY d.id), '[]') FROM documents d
                WHERE d.parcel_id = p.id AND d.kind = 'photo' AND d.uploaded_at IS NOT NULL) AS "photoKeys"
       FROM parcels p WHERE p.id = $1`,
      [id],
    );
    const row = rows[0] as (ListRow & { ownerId: number; titleRef: string | null; rejectionReason: string | null; photoKeys: string[] }) | undefined;
    const isOwner = row !== undefined && row.ownerId === viewerId;
    if (!row || (!isOwner && !PUBLIC_STATUSES.includes(row.status))) throw new ApiError(404, 'PARCEL_NOT_FOUND');
    const { ownerId, titleRef, rejectionReason, photoKeys, ...rest } = row;
    return {
      ...(await this.listItem(rest)),
      isOwner,
      photos: await Promise.all(photoKeys.map((key) => this.storage.presignGet(key))),
      ...(isOwner ? { titleRef, rejectionReason } : {}),
    };
  }

  async update(ownerId: number, id: number, patch: z.infer<typeof updateParcelSchema>) {
    const { rows } = await this.db
      .query(
        `UPDATE parcels SET title = COALESCE($3, title), price_gnf = COALESCE($4, price_gnf),
                deposit_gnf = CASE WHEN $5::boolean THEN $6 ELSE deposit_gnf END
         WHERE id = $1 AND owner_id = $2 AND status IN ('pending_verification', 'verified') RETURNING id`,
        [id, ownerId, patch.title ?? null, patch.priceGnf ?? null, patch.depositGnf !== undefined, patch.depositGnf ?? null],
      )
      .catch((error: DatabaseError) => {
        if (error.code === '23514') throw new ApiError(400, 'DEPOSIT_EXCEEDS_PRICE');
        throw error;
      });
    if (!rows[0]) await this.explainOwnerWriteFailure(ownerId, id);
    return this.detail(id, ownerId);
  }

  /** Boundaries never change (R2.10): withdrawing and resubmitting is the only way to redraw a plot. */
  async withdraw(ownerId: number, id: number) {
    const { rows } = await this.db.query(
      `UPDATE parcels SET status = 'withdrawn', verified_at = NULL, verified_by = NULL
       WHERE id = $1 AND owner_id = $2 AND status IN ('pending_verification', 'verified') RETURNING id`,
      [id, ownerId],
    );
    if (!rows[0]) await this.explainOwnerWriteFailure(ownerId, id);
    await audit(this.db, `user:${ownerId}`, 'parcel.withdrawn', 'parcel', id);
    return this.detail(id, ownerId);
  }

  private async explainOwnerWriteFailure(ownerId: number, id: number): Promise<never> {
    const { rows } = await this.db.query<{ status: string }>('SELECT status FROM parcels WHERE id = $1 AND owner_id = $2', [id, ownerId]);
    if (!rows[0]) throw new ApiError(404, 'PARCEL_NOT_FOUND');
    throw new ApiError(409, 'PARCEL_LOCKED', { status: rows[0].status });
  }

  async contact(userId: number, id: number) {
    const { rows } = await this.db.query<{ ownerId: number; sellerPhone: string; locale: 'fr' | 'en'; code: string; locality: string; prefecture: string; areaM2: number; priceGnf: number; verified: boolean }>(
      `SELECT p.owner_id AS "ownerId", seller.phone AS "sellerPhone", viewer.locale, p.code, p.locality, p.prefecture,
              p.area_m2 AS "areaM2", p.price_gnf AS "priceGnf", p.verified_at IS NOT NULL AS verified
       FROM parcels p JOIN users seller ON seller.id = p.owner_id JOIN users viewer ON viewer.id = $2
       WHERE p.id = $1 AND p.status = ANY($3)`,
      [id, userId, PUBLIC_STATUSES],
    );
    const row = rows[0];
    if (!row) throw new ApiError(404, 'PARCEL_NOT_FOUND');
    if (row.ownerId === userId) throw new ApiError(409, 'OWN_PARCEL');
    await this.db.query('INSERT INTO contact_leads (parcel_id, user_id) VALUES ($1, $2)', [id, userId]);
    return whatsappHandoff(row, row.locale);
  }

  async requestUpload(ownerId: number, parcelId: number, input: z.infer<typeof uploadSchema>) {
    const { rows } = await this.db.query<{ status: string; documents: number }>(
      'SELECT status, (SELECT count(*) FROM documents WHERE parcel_id = p.id)::int AS documents FROM parcels p WHERE id = $1 AND owner_id = $2',
      [parcelId, ownerId],
    );
    const parcel = rows[0];
    if (!parcel) throw new ApiError(404, 'PARCEL_NOT_FOUND');
    if (['rejected', 'withdrawn', 'sold'].includes(parcel.status)) throw new ApiError(409, 'PARCEL_LOCKED', { status: parcel.status });
    if (parcel.documents >= MAX_DOCUMENTS_PER_PARCEL) throw new ApiError(409, 'TOO_MANY_DOCUMENTS');
    const extension = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' }[input.contentType];
    const key = `parcels/${parcelId}/${input.kind}/${randomUUID()}.${extension}`;
    const inserted = await this.db.query<{ id: number }>(
      'INSERT INTO documents (parcel_id, kind, s3_key, content_type, size_bytes) VALUES ($1, $2, $3, $4, $5) RETURNING id',
      [parcelId, input.kind, key, input.contentType, input.sizeBytes],
    );
    return {
      documentId: inserted.rows[0]!.id,
      uploadUrl: await this.storage.presignPut(key, input.contentType, input.sizeBytes),
      method: 'PUT',
      headers: { 'content-type': input.contentType },
      expiresIn: 600,
    };
  }

  async completeUpload(ownerId: number, parcelId: number, documentId: number) {
    const { rows } = await this.db.query<{ s3_key: string; content_type: string; size_bytes: number }>(
      `SELECT d.s3_key, d.content_type, d.size_bytes FROM documents d JOIN parcels p ON p.id = d.parcel_id
       WHERE d.id = $1 AND d.parcel_id = $2 AND p.owner_id = $3`,
      [documentId, parcelId, ownerId],
    );
    const document = rows[0];
    if (!document) throw new ApiError(404, 'DOCUMENT_NOT_FOUND');
    const object = await this.storage.head(document.s3_key);
    if (!object) throw new ApiError(409, 'UPLOAD_MISSING');
    if (object.sizeBytes !== document.size_bytes || object.contentType !== document.content_type) throw new ApiError(422, 'UPLOAD_MISMATCH');
    await this.db.query('UPDATE documents SET uploaded_at = COALESCE(uploaded_at, now()) WHERE id = $1', [documentId]);
    return { documentId, uploaded: true };
  }

  /** Photos are public on public listings; deeds, survey plans and ID cards stay with the owner and staff (R3.3). */
  async documents(parcelId: number, viewerId?: number) {
    const parcel = await this.detail(parcelId, viewerId);
    const { rows } = await this.db.query<{ id: number; kind: string; contentType: string; s3Key: string }>(
      `SELECT id, kind, content_type AS "contentType", s3_key AS "s3Key" FROM documents
       WHERE parcel_id = $1 AND uploaded_at IS NOT NULL AND ($2 OR kind = 'photo') ORDER BY id`,
      [parcelId, parcel.isOwner],
    );
    return { items: await Promise.all(rows.map(async ({ s3Key, ...row }) => ({ ...row, url: await this.storage.presignGet(s3Key) }))) };
  }
}
