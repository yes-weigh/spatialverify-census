import { query } from '../db/pool.js';
import type { Asset, AssetStatus, GeometryType } from '../types/index.js';

function rowToAsset(row: Record<string, unknown>): Asset {
  return {
    id: row.id as string,
    project_id: row.project_id as string,
    category_id: row.category_id as string | null,
    name: row.name as string,
    description: row.description as string | null,
    status: row.status as AssetStatus,
    geometry_type: row.geometry_type as GeometryType,
    location: JSON.parse(row.location as string),
    altitude: row.altitude as number | null,
    heading: row.heading as number | null,
    metadata: row.metadata as Record<string, unknown>,
    created_by: row.created_by as string | null,
    verified_by: row.verified_by as string | null,
    verified_at: row.verified_at as string | null,
    client_id: row.client_id as string | null,
    version: row.version as number,
    created_at: row.created_at as string,
    updated_at: row.updated_at as string,
  };
}

const ASSET_SELECT = `
  id, project_id, category_id, name, description, status, geometry_type,
  ST_AsGeoJSON(location) as location, altitude, heading, metadata,
  created_by, verified_by, verified_at, client_id, version, created_at, updated_at
`;

export class AssetRepository {
  async findById(id: string): Promise<Asset | null> {
    const { rows } = await query(
      `SELECT ${ASSET_SELECT} FROM assets WHERE id = $1`,
      [id]
    );
    return rows[0] ? rowToAsset(rows[0]) : null;
  }

  async findByClientId(clientId: string): Promise<Asset | null> {
    const { rows } = await query(
      `SELECT ${ASSET_SELECT} FROM assets WHERE client_id = $1`,
      [clientId]
    );
    return rows[0] ? rowToAsset(rows[0]) : null;
  }

  async listByProject(projectId: string, status?: AssetStatus): Promise<Asset[]> {
    const params: unknown[] = [projectId];
    let sql = `SELECT ${ASSET_SELECT} FROM assets WHERE project_id = $1`;
    if (status) {
      sql += ' AND status = $2';
      params.push(status);
    }
    sql += ' ORDER BY created_at DESC';
    const { rows } = await query(sql, params);
    return rows.map(rowToAsset);
  }

  async create(data: {
    projectId: string;
    categoryId?: string;
    name: string;
    description?: string;
    status?: AssetStatus;
    geometryType: GeometryType;
    location: GeoJSON.Geometry;
    altitude?: number;
    heading?: number;
    metadata?: Record<string, unknown>;
    createdBy?: string;
    clientId?: string;
  }): Promise<Asset> {
    const { rows } = await query(
      `INSERT INTO assets (project_id, category_id, name, description, status, geometry_type,
                           location, altitude, heading, metadata, created_by, client_id)
       VALUES ($1, $2, $3, $4, $5, $6,
               ST_SetSRID(ST_GeomFromGeoJSON($7), 4326), $8, $9, $10, $11, $12)
       RETURNING ${ASSET_SELECT}`,
      [
        data.projectId,
        data.categoryId ?? null,
        data.name,
        data.description ?? null,
        data.status ?? 'pending',
        data.geometryType,
        JSON.stringify(data.location),
        data.altitude ?? null,
        data.heading ?? null,
        JSON.stringify(data.metadata ?? {}),
        data.createdBy ?? null,
        data.clientId ?? null,
      ]
    );
    return rowToAsset(rows[0]);
  }

  async updateStatus(
    id: string,
    status: AssetStatus,
    verifiedBy?: string
  ): Promise<Asset | null> {
    const { rows } = await query(
      `UPDATE assets SET status = $1, verified_by = $2, verified_at = CASE WHEN $2 IS NOT NULL THEN NOW() ELSE verified_at END,
                          version = version + 1
       WHERE id = $3
       RETURNING ${ASSET_SELECT}`,
      [status, verifiedBy ?? null, id]
    );
    return rows[0] ? rowToAsset(rows[0]) : null;
  }

  async searchRadius(
    projectId: string,
    lng: number,
    lat: number,
    radiusMeters: number,
    status?: AssetStatus
  ): Promise<Asset[]> {
    const params: unknown[] = [projectId, lng, lat, radiusMeters];
    let sql = `
      SELECT ${ASSET_SELECT},
             ST_Distance(location::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography) as distance
      FROM assets
      WHERE project_id = $1
        AND ST_DWithin(location::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)`;
    if (status) {
      sql += ' AND status = $5';
      params.push(status);
    }
    sql += ' ORDER BY distance';
    const { rows } = await query(sql, params);
    return rows.map(rowToAsset);
  }

  async searchBbox(
    projectId: string,
    minLng: number,
    minLat: number,
    maxLng: number,
    maxLat: number,
    status?: AssetStatus
  ): Promise<Asset[]> {
    const params: unknown[] = [projectId, minLng, minLat, maxLng, maxLat];
    let sql = `
      SELECT ${ASSET_SELECT} FROM assets
      WHERE project_id = $1
        AND location && ST_MakeEnvelope($2, $3, $4, $5, 4326)`;
    if (status) {
      sql += ' AND status = $6';
      params.push(status);
    }
    const { rows } = await query(sql, params);
    return rows.map(rowToAsset);
  }

  async nearby(
    projectId: string,
    lng: number,
    lat: number,
    limit: number = 20
  ): Promise<(Asset & { distance: number })[]> {
    const { rows } = await query(
      `SELECT ${ASSET_SELECT},
              ST_Distance(location::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography) as distance
       FROM assets
       WHERE project_id = $1
       ORDER BY location <-> ST_SetSRID(ST_MakePoint($2, $3), 4326)
       LIMIT $4`,
      [projectId, lng, lat, limit]
    );
    return rows.map((row) => ({
      ...rowToAsset(row),
      distance: parseFloat(row.distance as string),
    }));
  }

  async isInsideGeofence(projectId: string, lng: number, lat: number): Promise<boolean> {
    const { rows } = await query<{ inside: boolean }>(
      `SELECT ST_Contains(
        (SELECT boundary FROM projects WHERE id = $1),
        ST_SetSRID(ST_MakePoint($2, $3), 4326)
      ) as inside`,
      [projectId, lng, lat]
    );
    return rows[0]?.inside ?? false;
  }

  async countByStatus(projectId: string): Promise<Record<AssetStatus, number>> {
    const { rows } = await query<{ status: AssetStatus; count: string }>(
      'SELECT status, COUNT(*)::text as count FROM assets WHERE project_id = $1 GROUP BY status',
      [projectId]
    );
    const result: Record<string, number> = {
      not_surveyed: 0,
      pending: 0,
      verified: 0,
      rejected: 0,
    };
    for (const row of rows) {
      result[row.status] = parseInt(row.count, 10);
    }
    return result as Record<AssetStatus, number>;
  }
}

export const assetRepository = new AssetRepository();
