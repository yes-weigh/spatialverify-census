import { query } from '../db/pool.js';
import type { GeoJSONPolygon, HlbBoundary, HlbMissionPackage, MissionBoundaryAudit, OutsideBoundaryDiscovery } from '../types/hlb-boundary.js';
import { computeNorthWestStartPoint, exteriorRing } from '../utils/polygon-utils.js';

function mapBoundaryRow(row: Record<string, unknown>): HlbBoundary {
  const geojson = JSON.parse(String(row.boundary_geojson)) as GeoJSONPolygon;
  return {
    id: row.id as string,
    ebId: row.eb_id as string,
    hlbCode: row.hlb_code as string,
    name: (row.name as string) ?? null,
    boundaryPolygon: geojson,
    areaSqMeters: parseFloat(String(row.area_sq_meters)),
    northDescription: row.north_description as string | null,
    southDescription: row.south_description as string | null,
    eastDescription: row.east_description as string | null,
    westDescription: row.west_description as string | null,
    source: (row.source as 'official' | 'layout_map') ?? 'official',
    startPoint: {
      lat: parseFloat(String(row.start_lat)),
      lng: parseFloat(String(row.start_lng)),
    },
    importedAt: row.imported_at as string,
  };
}

export class HlbBoundaryRepository {
  async list(projectId?: string) {
    const params: unknown[] = [];
    let sql = `
      SELECT hb.*, ST_AsGeoJSON(hb.boundary)::text AS boundary_geojson, eb.project_id
      FROM hlb_boundaries hb
      JOIN enumeration_blocks eb ON eb.id = hb.eb_id`;
    if (projectId) {
      sql += ' WHERE eb.project_id = $1';
      params.push(projectId);
    }
    sql += ' ORDER BY hb.hlb_code';
    const { rows } = await query(sql, params);
    return rows.map(mapBoundaryRow);
  }

  async findById(id: string) {
    const { rows } = await query(
      `SELECT hb.*, ST_AsGeoJSON(hb.boundary)::text AS boundary_geojson, eb.project_id
       FROM hlb_boundaries hb
       JOIN enumeration_blocks eb ON eb.id = hb.eb_id
       WHERE hb.id = $1`,
      [id]
    );
    return rows[0] ? mapBoundaryRow(rows[0]) : null;
  }

  async findByEbId(ebId: string) {
    const { rows } = await query(
      `SELECT hb.*, ST_AsGeoJSON(hb.boundary)::text AS boundary_geojson
       FROM hlb_boundaries hb WHERE hb.eb_id = $1`,
      [ebId]
    );
    return rows[0] ? mapBoundaryRow(rows[0]) : null;
  }

  async findByHlbCode(projectId: string, hlbCode: string) {
    const { rows } = await query(
      `SELECT hb.*, ST_AsGeoJSON(hb.boundary)::text AS boundary_geojson
       FROM hlb_boundaries hb
       JOIN enumeration_blocks eb ON eb.id = hb.eb_id
       WHERE eb.project_id = $1 AND hb.hlb_code = $2`,
      [projectId, hlbCode]
    );
    return rows[0] ? mapBoundaryRow(rows[0]) : null;
  }

  async upsertBoundary(data: {
    ebId: string;
    hlbCode: string;
    name?: string;
    geoJson: GeoJSONPolygon;
    northDescription?: string;
    southDescription?: string;
    eastDescription?: string;
    westDescription?: string;
    startLat: number;
    startLng: number;
    source?: 'official' | 'layout_map';
  }) {
    const source = data.source ?? 'official';
    const ring = exteriorRing(data.geoJson);
    const { rows } = await query(
      `INSERT INTO hlb_boundaries (
         eb_id, hlb_code, name, boundary, area_sq_meters,
         north_description, south_description, east_description, west_description,
         start_lat, start_lng, source, imported_at, updated_at
       ) VALUES (
         $1, $2, $3,
         ST_SetSRID(ST_GeomFromGeoJSON($4), 4326),
         ST_Area(ST_SetSRID(ST_GeomFromGeoJSON($4), 4326)::geography),
         $5, $6, $7, $8, $9, $10, $11, NOW(), NOW()
       )
       ON CONFLICT (eb_id) DO UPDATE SET
         hlb_code = EXCLUDED.hlb_code,
         name = EXCLUDED.name,
         boundary = EXCLUDED.boundary,
         area_sq_meters = EXCLUDED.area_sq_meters,
         north_description = EXCLUDED.north_description,
         south_description = EXCLUDED.south_description,
         east_description = EXCLUDED.east_description,
         west_description = EXCLUDED.west_description,
         start_lat = EXCLUDED.start_lat,
         start_lng = EXCLUDED.start_lng,
         source = EXCLUDED.source,
         imported_at = NOW(),
         updated_at = NOW()
       RETURNING *, ST_AsGeoJSON(boundary)::text AS boundary_geojson`,
      [
        data.ebId,
        data.hlbCode,
        data.name ?? null,
        JSON.stringify(data.geoJson),
        data.northDescription ?? null,
        data.southDescription ?? null,
        data.eastDescription ?? null,
        data.westDescription ?? null,
        data.startLat,
        data.startLng,
        source,
      ]
    );

    await query(
      `UPDATE enumeration_blocks SET boundary = ST_SetSRID(ST_GeomFromGeoJSON($2), 4326), updated_at = NOW() WHERE id = $1`,
      [data.ebId, JSON.stringify(data.geoJson)]
    );

    return mapBoundaryRow(rows[0]);
  }

  async importFromWkt(ebId: string, hlbCode: string, wkt: string, meta: {
    name?: string;
    northDescription?: string;
    southDescription?: string;
    eastDescription?: string;
    westDescription?: string;
  }) {
    const { rows } = await query(
      `SELECT ST_AsGeoJSON(ST_SetSRID(ST_GeomFromText($1), 4326))::text AS geojson,
              ST_Area(ST_SetSRID(ST_GeomFromText($1), 4326)::geography) AS area`,
      [wkt]
    );
    const geojson = JSON.parse(rows[0].geojson as string) as GeoJSONPolygon;
    const ring = exteriorRing(geojson);
    const start = computeNorthWestStartPoint(ring);
    return this.upsertBoundary({
      ebId,
      hlbCode,
      geoJson: geojson,
      startLat: start.lat,
      startLng: start.lng,
      ...meta,
    });
  }

  async getMissionPackage(boundaryId: string): Promise<HlbMissionPackage | null> {
    const boundary = await this.findById(boundaryId);
    if (!boundary) return null;
    return this.buildMissionPackage(boundary.ebId, boundary);
  }

  async getMissionPackageByEbId(ebId: string): Promise<HlbMissionPackage | null> {
    const boundary = await this.findByEbId(ebId);
    if (!boundary) return null;
    return this.buildMissionPackage(ebId, boundary);
  }

  private async buildMissionPackage(ebId: string, boundary: HlbBoundary): Promise<HlbMissionPackage | null> {
    const { rows } = await query(
      `SELECT eb.*,
        (SELECT COUNT(*)::int FROM mission_buildings mb WHERE mb.eb_id = eb.id) AS total_buildings
       FROM enumeration_blocks eb WHERE eb.id = $1`,
      [ebId]
    );
    const block = rows[0];
    if (!block) return null;

    const buildingsDiscovered = block.total_buildings as number;
    const phase = block.status === 'published' && buildingsDiscovered > 0 ? 'listing' : 'mapping';
    const audit = await this.getAudit(ebId);

    return {
      boundary,
      ebId,
      ebCode: block.eb_code as string,
      projectId: block.project_id as string,
      phase,
      audit,
    };
  }

  async getAudit(ebId: string): Promise<MissionBoundaryAudit | null> {
    const { rows } = await query(`SELECT * FROM mission_boundary_audit WHERE eb_id = $1`, [ebId]);
    const row = rows[0];
    if (!row) return null;
    return {
      ebId,
      enumeratorId: row.enumerator_id as string | null,
      enteredBoundaryAt: row.entered_boundary_at as string | null,
      leftBoundaryAt: row.left_boundary_at as string | null,
      startPointReachedAt: row.start_point_reached_at as string | null,
      discoveryStartedAt: row.discovery_started_at as string | null,
      outsideBoundaryDiscoveries: (row.outside_boundary_discoveries as OutsideBoundaryDiscovery[]) ?? [],
    };
  }

  async upsertAudit(ebId: string, patch: Partial<MissionBoundaryAudit> & { enumeratorId?: string }) {
    await query(
      `INSERT INTO mission_boundary_audit (eb_id, enumerator_id, entered_boundary_at, left_boundary_at,
         start_point_reached_at, discovery_started_at, outside_boundary_discoveries, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW())
       ON CONFLICT (eb_id) DO UPDATE SET
         enumerator_id = COALESCE(EXCLUDED.enumerator_id, mission_boundary_audit.enumerator_id),
         entered_boundary_at = COALESCE(EXCLUDED.entered_boundary_at, mission_boundary_audit.entered_boundary_at),
         left_boundary_at = COALESCE(EXCLUDED.left_boundary_at, mission_boundary_audit.left_boundary_at),
         start_point_reached_at = COALESCE(EXCLUDED.start_point_reached_at, mission_boundary_audit.start_point_reached_at),
         discovery_started_at = COALESCE(EXCLUDED.discovery_started_at, mission_boundary_audit.discovery_started_at),
         outside_boundary_discoveries = COALESCE(EXCLUDED.outside_boundary_discoveries, mission_boundary_audit.outside_boundary_discoveries),
         updated_at = NOW()`,
      [
        ebId,
        patch.enumeratorId ?? null,
        patch.enteredBoundaryAt ?? null,
        patch.leftBoundaryAt ?? null,
        patch.startPointReachedAt ?? null,
        patch.discoveryStartedAt ?? null,
        JSON.stringify(patch.outsideBoundaryDiscoveries ?? []),
      ]
    );
  }

  async appendOutsideDiscovery(ebId: string, discovery: {
    latitude: number;
    longitude: number;
    label: string;
    overridden: boolean;
  }) {
    const audit = (await this.getAudit(ebId)) ?? {
      ebId,
      outsideBoundaryDiscoveries: [],
    };
    const updated = [
      ...audit.outsideBoundaryDiscoveries,
      { ...discovery, recordedAt: new Date().toISOString() },
    ];
    await this.upsertAudit(ebId, { outsideBoundaryDiscoveries: updated });
  }
}

export const hlbBoundaryRepository = new HlbBoundaryRepository();
