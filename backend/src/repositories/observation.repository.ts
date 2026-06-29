import { query } from '../db/pool.js';
import { EMBEDDING_DIMENSION, IDENTITY_THRESHOLDS } from '../types/identity.js';
import type { GpsCluster, HeadingProfile, ViewType } from '../types/identity.js';
import { encodeGeohash, geohashSearchCells } from '../utils/geohash.js';

export function formatVector(embedding: number[]): string {
  if (embedding.length !== EMBEDDING_DIMENSION) {
    throw new Error(`Embedding must be ${EMBEDDING_DIMENSION} dimensions, got ${embedding.length}`);
  }
  return `[${embedding.join(',')}]`;
}

export class ObservationRepository {
  async create(data: {
    projectId: string;
    assetId?: string;
    embedding: number[];
    latitude: number;
    longitude: number;
    altitude?: number;
    accuracy?: number;
    verticalAccuracy?: number;
    heading?: number;
    bearingAccuracy?: number;
    viewType?: ViewType;
    categoryLabel?: string;
    weather?: string;
    lighting?: string;
    detectionId?: string;
    imageId?: string;
    capturedBy?: string;
    clientId?: string;
    deviceModel?: string;
    cameraFov?: number;
    cameraResolution?: string;
  }) {
    const vector = formatVector(data.embedding);
    const geohash = encodeGeohash(data.latitude, data.longitude, IDENTITY_THRESHOLDS.geohashPrecision);

    const { rows } = await query(
      `INSERT INTO asset_observations (
        project_id, asset_id, detection_id, image_id,
        latitude, longitude, altitude, accuracy, vertical_accuracy,
        heading, bearing_accuracy, embedding, view_type,
        category_label, weather, lighting, location, captured_by, client_id,
        device_model, camera_fov, camera_resolution, geohash
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::vector,
        $13, $14, $15, $16,
        ST_SetSRID(ST_MakePoint($6, $5), 4326),
        $17, $18, $19, $20, $21, $22
      ) RETURNING *`,
      [
        data.projectId, data.assetId ?? null, data.detectionId ?? null, data.imageId ?? null,
        data.latitude, data.longitude, data.altitude ?? null,
        data.accuracy ?? null, data.verticalAccuracy ?? null,
        data.heading ?? null, data.bearingAccuracy ?? null,
        vector, data.viewType ?? 'unknown',
        data.categoryLabel ?? null, data.weather ?? null, data.lighting ?? null,
        data.capturedBy ?? null, data.clientId ?? null,
        data.deviceModel ?? null, data.cameraFov ?? null, data.cameraResolution ?? null,
        geohash,
      ]
    );
    return rows[0];
  }

  async findByAsset(assetId: string) {
    const { rows } = await query(
      `SELECT * FROM asset_observations WHERE asset_id = $1 ORDER BY captured_at DESC`,
      [assetId]
    );
    return rows;
  }

  async getEmbeddingsByAsset(assetId: string): Promise<number[][]> {
    const { rows } = await query<{ embedding: string }>(
      `SELECT embedding::text FROM asset_observations WHERE asset_id = $1 ORDER BY captured_at`,
      [assetId]
    );
    return rows.map((r) => parseVector(r.embedding));
  }

  /**
   * Two-phase identity search (Sprint 1):
   *   Phase 1 — project + geohash bucket + ST_DWithin → cap at geoCandidateLimit
   *   Phase 2 — vector rank on bounded subset → observationSearchLimit
   */
  async searchObservations(
    projectId: string,
    embedding: number[],
    limit: number = IDENTITY_THRESHOLDS.observationSearchLimit,
    radiusMeters: number = IDENTITY_THRESHOLDS.searchRadiusMeters,
    latitude?: number,
    longitude?: number,
    geoCandidateLimit: number = IDENTITY_THRESHOLDS.geoCandidateLimit
  ) {
    const vector = formatVector(embedding);

    if (latitude == null || longitude == null) {
      return this.searchObservationsGlobal(projectId, embedding, limit);
    }

    const geohashCells = geohashSearchCells(
      latitude,
      longitude,
      IDENTITY_THRESHOLDS.geohashPrecision
    );

    const { rows } = await query(
      `WITH geo_candidates AS (
        SELECT
          ao.id,
          ao.asset_id,
          ao.category_label,
          ao.view_type,
          ao.heading,
          ao.captured_at,
          ao.accuracy,
          ao.embedding,
          ST_Distance(
            ao.location::geography,
            ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
          )::float AS distance_meters
        FROM asset_observations ao
        WHERE ao.project_id = $2
          AND ao.asset_id IS NOT NULL
          AND ao.geohash = ANY($7::text[])
          AND ST_DWithin(
            ao.location::geography,
            ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography,
            $5
          )
        ORDER BY distance_meters ASC
        LIMIT $6
      ),
      ranked AS (
        SELECT
          gc.*,
          (gc.embedding <=> $1::vector)::float AS cosine_distance
        FROM geo_candidates gc
        ORDER BY gc.embedding <=> $1::vector
        LIMIT $8
      )
      SELECT
        r.id AS observation_id,
        r.asset_id,
        a.name AS asset_name,
        r.category_label,
        r.view_type,
        r.heading,
        r.captured_at,
        r.accuracy,
        r.cosine_distance,
        r.distance_meters,
        r.distance_meters AS distance_to_observation_m,
        CASE WHEN a.gps_centroid IS NOT NULL THEN
          ST_Distance(
            a.gps_centroid::geography,
            ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
          )::float
        ELSE NULL END AS distance_to_centroid_m,
        a.gps_variance_m2,
        a.gps_radius_m,
        a.observation_count,
        a.heading_mean,
        a.heading_variance,
        a.visual_drift_score,
        a.last_observation_at
      FROM ranked r
      JOIN assets a ON a.id = r.asset_id
      ORDER BY r.cosine_distance ASC`,
      [
        vector,
        projectId,
        longitude,
        latitude,
        radiusMeters,
        geoCandidateLimit,
        geohashCells,
        limit,
      ]
    );

    return rows;
  }

  /** Fallback when GPS is unavailable — vector-only search within project. */
  private async searchObservationsGlobal(
    projectId: string,
    embedding: number[],
    limit: number
  ) {
    const vector = formatVector(embedding);
    const { rows } = await query(
      `SELECT
        ao.id AS observation_id,
        ao.asset_id,
        a.name AS asset_name,
        ao.category_label,
        ao.view_type,
        ao.heading,
        ao.captured_at,
        ao.accuracy,
        (ao.embedding <=> $1::vector)::float AS cosine_distance,
        NULL::float AS distance_meters,
        NULL::float AS distance_to_observation_m,
        NULL::float AS distance_to_centroid_m,
        a.gps_variance_m2,
        a.gps_radius_m,
        a.observation_count,
        a.heading_mean,
        a.heading_variance,
        a.visual_drift_score,
        a.last_observation_at
       FROM asset_observations ao
       JOIN assets a ON a.id = ao.asset_id
       WHERE ao.project_id = $2 AND ao.asset_id IS NOT NULL
       ORDER BY ao.embedding <=> $1::vector
       LIMIT $3`,
      [vector, projectId, limit]
    );
    return rows;
  }

  async backfillGeohash(batchSize = 5000): Promise<number> {
    const { rows: pending } = await query<{ id: string; latitude: number; longitude: number }>(
      `SELECT id, latitude, longitude FROM asset_observations WHERE geohash IS NULL LIMIT $1`,
      [batchSize]
    );

    if (pending.length === 0) return 0;

    for (const row of pending) {
      const geohash = encodeGeohash(row.latitude, row.longitude, IDENTITY_THRESHOLDS.geohashPrecision);
      await query(`UPDATE asset_observations SET geohash = $1 WHERE id = $2`, [geohash, row.id]);
    }

    return pending.length;
  }

  async updateAssetFingerprint(assetId: string) {
    const { rows: stats } = await query(
      `WITH obs AS (
        SELECT location, heading, captured_at
        FROM asset_observations
        WHERE asset_id = $1
      ),
      centroid AS (
        SELECT ST_Centroid(ST_Collect(location::geometry)) AS center FROM obs
      )
      SELECT
        COUNT(*)::int AS obs_count,
        ST_Y(c.center) AS centroid_lat,
        ST_X(c.center) AS centroid_lng,
        AVG(POWER(ST_Distance(o.location::geography, c.center::geography), 2)) AS variance_m2,
        MAX(ST_Distance(o.location::geography, c.center::geography)) AS radius_m,
        AVG(o.heading) FILTER (WHERE o.heading IS NOT NULL) AS heading_mean,
        VARIANCE(o.heading) FILTER (WHERE o.heading IS NOT NULL) AS heading_variance,
        MAX(o.captured_at) AS last_observation_at
       FROM obs o
       CROSS JOIN centroid c
       GROUP BY c.center`,
      [assetId]
    );

    if (!stats[0] || stats[0].obs_count === 0) return null;

    const s = stats[0];
    const variance = parseFloat(String(s.variance_m2 ?? 0)) || 0;
    const radius = Math.max(parseFloat(String(s.radius_m ?? 0)) || 0, 3);

    await query(
      `UPDATE assets SET
        gps_centroid = ST_SetSRID(ST_MakePoint($1, $2), 4326),
        gps_variance_m2 = $3,
        gps_radius_m = $4,
        observation_count = $5,
        heading_mean = $6,
        heading_variance = $7,
        last_observation_at = $8,
        updated_at = NOW()
       WHERE id = $9`,
      [
        parseFloat(String(s.centroid_lng)),
        parseFloat(String(s.centroid_lat)),
        variance,
        radius,
        s.obs_count,
        s.heading_mean ?? null,
        s.heading_variance ?? null,
        s.last_observation_at ?? null,
        assetId,
      ]
    );

    return {
      centroid_lat: parseFloat(String(s.centroid_lat)),
      centroid_lng: parseFloat(String(s.centroid_lng)),
      variance_m2: variance,
      radius_m: radius,
      observation_count: s.obs_count as number,
    };
  }

  async getAssetCluster(assetId: string): Promise<GpsCluster | null> {
    const { rows } = await query(
      `SELECT
        ST_Y(gps_centroid::geometry) as centroid_lat,
        ST_X(gps_centroid::geometry) as centroid_lng,
        gps_variance_m2 as variance_m2,
        gps_radius_m as radius_m,
        observation_count
       FROM assets WHERE id = $1 AND gps_centroid IS NOT NULL`,
      [assetId]
    );
    if (!rows[0]) return null;
    const r = rows[0];
    return {
      centroid_lat: parseFloat(String(r.centroid_lat)),
      centroid_lng: parseFloat(String(r.centroid_lng)),
      variance_m2: parseFloat(String(r.variance_m2 ?? 0)),
      radius_m: parseFloat(String(r.radius_m ?? 0)),
      observation_count: r.observation_count as number,
    };
  }

  async getHeadingProfile(assetId: string): Promise<HeadingProfile> {
    const { rows } = await query(
      `SELECT heading_mean as mean, heading_variance as variance FROM assets WHERE id = $1`,
      [assetId]
    );
    return {
      mean: rows[0]?.mean != null ? parseFloat(String(rows[0].mean)) : null,
      variance: rows[0]?.variance != null ? parseFloat(String(rows[0].variance)) : null,
    };
  }

  async updateVisualDrift(assetId: string, driftScore: number) {
    await query(
      `UPDATE assets SET visual_drift_score = $1, updated_at = NOW() WHERE id = $2`,
      [driftScore, assetId]
    );
  }

  async getCategoryLabelGroups(projectId: string): Promise<string[][]> {
    const { rows } = await query<{ detection_labels: string[] }>(
      `SELECT detection_labels FROM asset_categories WHERE project_id = $1`,
      [projectId]
    );
    return rows.map((r) => r.detection_labels);
  }

  async countObservations(projectId?: string): Promise<number> {
    if (projectId) {
      const { rows } = await query<{ count: string }>(
        `SELECT COUNT(*)::text AS count FROM asset_observations WHERE project_id = $1`,
        [projectId]
      );
      return parseInt(rows[0].count, 10);
    }
    const { rows } = await query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM asset_observations`
    );
    return parseInt(rows[0].count, 10);
  }
}

function parseVector(text: string): number[] {
  return text
    .replace('[', '')
    .replace(']', '')
    .split(',')
    .map((v) => parseFloat(v.trim()));
}

export const observationRepository = new ObservationRepository();
