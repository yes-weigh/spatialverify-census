import { query } from '../db/pool.js';
import { EMBEDDING_DIMENSION } from '../types/identity.js';

export function formatVector(embedding: number[]): string {
  if (embedding.length !== EMBEDDING_DIMENSION) {
    throw new Error(`Embedding must be ${EMBEDDING_DIMENSION} dimensions, got ${embedding.length}`);
  }
  return `[${embedding.join(',')}]`;
}

export class EmbeddingRepository {
  async create(data: {
    projectId: string;
    assetId: string;
    embedding: number[];
    imageId?: string;
    detectionId?: string;
    modelName?: string;
    categoryLabel?: string;
    heading?: number;
    latitude?: number;
    longitude?: number;
    capturedBy?: string;
    clientId?: string;
  }) {
    const vector = formatVector(data.embedding);
    const hasLocation = data.latitude != null && data.longitude != null;

    const { rows } = await query(
      `INSERT INTO asset_embeddings (
        project_id, asset_id, image_id, detection_id, model_name, embedding,
        category_label, heading, location, captured_by, client_id
      ) VALUES (
        $1, $2, $3, $4, $5, $6::vector, $7, $8,
        ${hasLocation ? 'ST_SetSRID(ST_MakePoint($11, $12), 4326)' : 'NULL'},
        $9, $10
      ) RETURNING id, project_id, asset_id, image_id, detection_id, model_name,
                  category_label, heading, captured_by, client_id, created_at`,
      hasLocation
        ? [
            data.projectId, data.assetId, data.imageId ?? null, data.detectionId ?? null,
            data.modelName ?? 'mobilenet_v2', vector, data.categoryLabel ?? null,
            data.heading ?? null, data.capturedBy ?? null, data.clientId ?? null,
            data.longitude!, data.latitude!,
          ]
        : [
            data.projectId, data.assetId, data.imageId ?? null, data.detectionId ?? null,
            data.modelName ?? 'mobilenet_v2', vector, data.categoryLabel ?? null,
            data.heading ?? null, data.capturedBy ?? null, data.clientId ?? null,
          ]
    );
    return rows[0];
  }

  async findByAsset(assetId: string) {
    const { rows } = await query(
      `SELECT id, project_id, asset_id, image_id, detection_id, model_name,
              category_label, heading, captured_by, client_id, created_at
       FROM asset_embeddings WHERE asset_id = $1 ORDER BY created_at DESC`,
      [assetId]
    );
    return rows;
  }

  async searchSimilar(
    projectId: string,
    embedding: number[],
    limit = 10,
    radiusMeters = 50,
    latitude?: number,
    longitude?: number
  ) {
    const vector = formatVector(embedding);

    if (latitude != null && longitude != null) {
      const { rows } = await query(
        `SELECT
          ae.asset_id,
          a.name as asset_name,
          ae.category_label,
          ae.heading,
          (ae.embedding <=> $1::vector)::float as cosine_distance,
          ST_Distance(
            ae.location::geography,
            ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography
          )::float as distance_meters
         FROM asset_embeddings ae
         JOIN assets a ON a.id = ae.asset_id
         WHERE ae.project_id = $2
           AND ae.location IS NOT NULL
           AND ST_DWithin(
             ae.location::geography,
             ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography,
             $5
           )
         ORDER BY ae.embedding <=> $1::vector
         LIMIT $6`,
        [vector, projectId, longitude, latitude, radiusMeters, limit]
      );
      return rows;
    }

    const { rows } = await query(
      `SELECT
        ae.asset_id,
        a.name as asset_name,
        ae.category_label,
        ae.heading,
        (ae.embedding <=> $1::vector)::float as cosine_distance,
        NULL::float as distance_meters
       FROM asset_embeddings ae
       JOIN assets a ON a.id = ae.asset_id
       WHERE ae.project_id = $2
       ORDER BY ae.embedding <=> $1::vector
       LIMIT $3`,
      [vector, projectId, limit]
    );
    return rows;
  }

  async getCategoryLabelGroups(projectId: string): Promise<string[][]> {
    const { rows } = await query<{ detection_labels: string[] }>(
      `SELECT detection_labels FROM asset_categories WHERE project_id = $1`,
      [projectId]
    );
    return rows.map((r: { detection_labels: string[] }) => r.detection_labels);
  }
}

export class IdentityResolutionRepository {
  async create(data: {
    projectId: string;
    detectionId?: string;
    queryCategory: string;
    latitude: number;
    longitude: number;
    queryHeading?: number;
    queryEmbedding?: number[];
    matchedAssetId?: string;
    verdict: string;
    gpsScore: number;
    embeddingScore: number;
    categoryScore: number;
    headingScore: number;
    finalConfidence: number;
    candidateScores: unknown[];
    resolutionStatus: string;
    conflictId?: string;
    createdBy?: string;
    clientId?: string;
    gpsAccuracy?: number;
    explanation?: unknown;
    viewScores?: unknown[];
    matchedViewType?: string;
    visualDrift?: number | null;
    lastSeenAt?: string | null;
  }) {
    const embeddingParam = data.queryEmbedding ? formatVector(data.queryEmbedding) : null;

    const { rows } = await query(
      `INSERT INTO identity_resolutions (
        project_id, detection_id, query_category, query_location, query_heading,
        query_embedding, matched_asset_id, verdict, gps_score, embedding_score,
        category_score, heading_score, final_confidence, candidate_scores,
        resolution_status, conflict_id, created_by, client_id,
        gps_accuracy, explanation, view_scores, matched_view_type, visual_drift, last_seen_at
      ) VALUES (
        $1, $2, $3,
        ST_SetSRID(ST_MakePoint($4, $5), 4326),
        $6, $7::vector, $8, $9, $10, $11, $12, $13, $14, $15::jsonb,
        $16, $17, $18, $19,
        $20, $21::jsonb, $22::jsonb, $23, $24, $25
      ) RETURNING *`,
      [
        data.projectId,
        data.detectionId ?? null,
        data.queryCategory,
        data.longitude,
        data.latitude,
        data.queryHeading ?? null,
        embeddingParam,
        data.matchedAssetId ?? null,
        data.verdict,
        data.gpsScore,
        data.embeddingScore,
        data.categoryScore,
        data.headingScore,
        data.finalConfidence,
        JSON.stringify(data.candidateScores),
        data.resolutionStatus,
        data.conflictId ?? null,
        data.createdBy ?? null,
        data.clientId ?? null,
        data.gpsAccuracy ?? null,
        JSON.stringify(data.explanation ?? {}),
        JSON.stringify(data.viewScores ?? []),
        data.matchedViewType ?? null,
        data.visualDrift ?? null,
        data.lastSeenAt ?? null,
      ]
    );
    return rows[0];
  }

  async findById(id: string) {
    const { rows } = await query('SELECT * FROM identity_resolutions WHERE id = $1', [id]);
    return rows[0] ?? null;
  }

  async listPending(projectId?: string) {
    const params: unknown[] = [];
    let sql = `SELECT * FROM identity_resolutions
               WHERE resolution_status = 'pending' AND verdict = 'possible_match'`;
    if (projectId) {
      sql += ' AND project_id = $1';
      params.push(projectId);
    }
    sql += ' ORDER BY created_at DESC';
    const { rows } = await query(sql, params);
    return rows;
  }

  async resolve(id: string, status: string, resolvedBy: string, matchedAssetId?: string) {
    const { rows } = await query(
      `UPDATE identity_resolutions
       SET resolution_status = $1, resolved_by = $2, resolved_at = NOW(),
           matched_asset_id = COALESCE($4, matched_asset_id)
       WHERE id = $3 RETURNING *`,
      [status, resolvedBy, id, matchedAssetId ?? null]
    );
    return rows[0] ?? null;
  }
}

export const embeddingRepository = new EmbeddingRepository();
export const identityResolutionRepository = new IdentityResolutionRepository();
