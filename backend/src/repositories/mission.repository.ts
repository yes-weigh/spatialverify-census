import { query } from '../db/pool.js';
import type {
  EbStatus,
  MapPoint,
  MissionBuildingStatus,
  SaveMissionPlanInput,
} from '../types/mission.js';

export class MissionRepository {
  async listBlocks(projectId: string, userId?: string) {
    const params: unknown[] = [projectId];
    let sql = `
      SELECT eb.*,
        (SELECT COUNT(*)::int FROM mission_buildings mb WHERE mb.eb_id = eb.id) AS total_buildings,
        (SELECT COUNT(*)::int FROM mission_buildings mb WHERE mb.eb_id = eb.id AND mb.status = 'completed') AS completed_buildings
      FROM enumeration_blocks eb
      WHERE eb.project_id = $1`;

    if (userId) {
      sql += ` AND eb.created_by = $2`;
      params.push(userId);
    }

    sql += ' ORDER BY eb.updated_at DESC';
    const { rows } = await query(sql, params);
    return rows;
  }

  async findBlockById(id: string) {
    const { rows } = await query(
      `SELECT eb.*,
        u.first_name || ' ' || u.last_name AS enumerator_name
       FROM enumeration_blocks eb
       LEFT JOIN users u ON u.id = eb.assigned_enumerator_id
       WHERE eb.id = $1`,
      [id]
    );
    return rows[0] ?? null;
  }

  async findBlockByProjectAndCode(projectId: string, ebCode: string) {
    const { rows } = await query(
      `SELECT * FROM enumeration_blocks WHERE project_id = $1 AND eb_code = $2`,
      [projectId, ebCode]
    );
    return rows[0] ?? null;
  }

  async createBlock(data: {
    projectId: string;
    ebCode: string;
    name?: string;
    assignedEnumeratorId?: string;
    createdBy: string;
  }) {
    const { rows } = await query(
      `INSERT INTO enumeration_blocks (project_id, eb_code, name, assigned_enumerator_id, created_by)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [data.projectId, data.ebCode, data.name ?? null, data.assignedEnumeratorId ?? null, data.createdBy]
    );
    return rows[0];
  }

  async updateLayoutImage(id: string, key: string, mime: string) {
    const { rows } = await query(
      `UPDATE enumeration_blocks SET layout_image_key = $1, layout_image_mime = $2, updated_at = NOW()
       WHERE id = $3 RETURNING *`,
      [key, mime, id]
    );
    return rows[0] ?? null;
  }

  async updateBlockMeta(
    id: string,
    data: {
      name?: string;
      status?: EbStatus;
      assignedEnumeratorId?: string | null;
      boundaryMap?: MapPoint[];
      northBearing?: number;
      routeBuildingIds?: string[];
    }
  ) {
    const sets: string[] = ['updated_at = NOW()'];
    const params: unknown[] = [];
    let i = 1;

    if (data.name !== undefined) { sets.push(`name = $${i++}`); params.push(data.name); }
    if (data.status !== undefined) {
      sets.push(`status = $${i++}::eb_status`);
      params.push(data.status);
      if (data.status === 'published') sets.push('published_at = NOW()');
    }
    if (data.assignedEnumeratorId !== undefined) {
      sets.push(`assigned_enumerator_id = $${i++}`);
      params.push(data.assignedEnumeratorId);
    }
    if (data.boundaryMap !== undefined) {
      sets.push(`boundary_map = $${i++}::jsonb`);
      params.push(JSON.stringify(data.boundaryMap));
    }
    if (data.northBearing !== undefined) {
      sets.push(`north_bearing = $${i++}`);
      params.push(data.northBearing);
    }
    if (data.routeBuildingIds !== undefined) {
      sets.push(`route_building_ids = $${i++}`);
      params.push(data.routeBuildingIds);
    }

    params.push(id);
    const { rows } = await query(
      `UPDATE enumeration_blocks SET ${sets.join(', ')} WHERE id = $${i} RETURNING *`,
      params
    );
    return rows[0] ?? null;
  }

  async getBuildings(ebId: string) {
    const { rows } = await query(
      `SELECT id, eb_id, building_number, census_house_count, building_type,
              map_x, map_y, route_sequence, status, notes, asset_id,
              visited_at, completed_at, completed_by,
              ST_Y(location::geometry) AS latitude,
              ST_X(location::geometry) AS longitude
       FROM mission_buildings WHERE eb_id = $1
       ORDER BY COALESCE(route_sequence, building_number), building_number`,
      [ebId]
    );
    return rows;
  }

  async getLandmarks(ebId: string) {
    const { rows } = await query(
      `SELECT * FROM mission_landmarks WHERE eb_id = $1 ORDER BY name`,
      [ebId]
    );
    return rows;
  }

  async replaceMissionPlan(ebId: string, plan: SaveMissionPlanInput) {
    await query('DELETE FROM mission_landmarks WHERE eb_id = $1', [ebId]);
    await query('DELETE FROM mission_buildings WHERE eb_id = $1', [ebId]);

    const buildingIds: string[] = [];

    for (const b of plan.buildings) {
      const hasLocation = b.latitude != null && b.longitude != null;
      const { rows } = await query(
        `INSERT INTO mission_buildings (
          eb_id, building_number, census_house_count, building_type,
          map_x, map_y, route_sequence, location
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7,
          ${hasLocation ? 'ST_SetSRID(ST_MakePoint($9, $8), 4326)' : 'NULL'}
        ) RETURNING id`,
        hasLocation
          ? [ebId, b.buildingNumber, b.censusHouseCount, b.buildingType, b.mapX, b.mapY, b.routeSequence ?? null, b.latitude, b.longitude]
          : [ebId, b.buildingNumber, b.censusHouseCount, b.buildingType, b.mapX, b.mapY, b.routeSequence ?? null]
      );
      buildingIds.push(rows[0].id as string);
    }

    for (const lm of plan.landmarks) {
      await query(
        `INSERT INTO mission_landmarks (eb_id, name, landmark_type, map_x, map_y)
         VALUES ($1, $2, $3, $4, $5)`,
        [ebId, lm.name, lm.landmarkType, lm.mapX, lm.mapY]
      );
    }

    const routeIds = plan.routeBuildingIds?.length ? plan.routeBuildingIds : buildingIds;

    await query(
      `UPDATE enumeration_blocks SET
        boundary_map = $1::jsonb,
        north_bearing = COALESCE($2, north_bearing),
        route_building_ids = $3,
        updated_at = NOW()
       WHERE id = $4`,
      [JSON.stringify(plan.boundaryMap), plan.northBearing ?? null, routeIds, ebId]
    );

    return { buildingIds, routeIds };
  }

  async updateBuildingStatus(
    buildingId: string,
    status: MissionBuildingStatus,
    userId: string,
    notes?: string,
    assetId?: string,
    latitude?: number,
    longitude?: number,
  ) {
    const hasLocation = latitude != null && longitude != null;
    const { rows } = await query(
      `UPDATE mission_buildings SET
        status = $1::mission_building_status,
        notes = COALESCE($2, notes),
        asset_id = COALESCE($3, asset_id),
        location = CASE WHEN $6 AND $7 IS NOT NULL AND $8 IS NOT NULL
          THEN ST_SetSRID(ST_MakePoint($8, $7), 4326) ELSE location END,
        visited_at = CASE WHEN $1::text IN ('visited', 'completed')
          THEN COALESCE(visited_at, NOW()) ELSE visited_at END,
        completed_at = CASE WHEN $1::text = 'completed' THEN NOW() ELSE completed_at END,
        completed_by = CASE WHEN $1::text = 'completed' THEN $4 ELSE completed_by END,
        updated_at = NOW()
       WHERE id = $5 RETURNING *`,
      [status, notes ?? null, assetId ?? null, userId, buildingId, hasLocation, latitude, longitude]
    );
    return rows[0] ?? null;
  }

  async getBuildingById(buildingId: string) {
    const { rows } = await query(
      `SELECT *, ST_Y(location::geometry) AS latitude, ST_X(location::geometry) AS longitude
       FROM mission_buildings WHERE id = $1`,
      [buildingId]
    );
    return rows[0] ?? null;
  }

  async getBuildingStats(ebId: string) {
    const { rows } = await query(
      `SELECT
        COUNT(*)::int AS total,
        COUNT(*) FILTER (WHERE status = 'completed')::int AS completed,
        COUNT(*) FILTER (WHERE status = 'visited')::int AS visited,
        COUNT(*) FILTER (WHERE status = 'revisit_required')::int AS revisit,
        COUNT(*) FILTER (WHERE status = 'not_visited')::int AS not_visited
       FROM mission_buildings WHERE eb_id = $1`,
      [ebId]
    );
    return rows[0];
  }

  async addBreadcrumb(ebId: string, userId: string, lat: number, lng: number, accuracy?: number) {
    const { rows } = await query(
      `INSERT INTO mission_gps_breadcrumbs (eb_id, user_id, location, accuracy)
       VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326), $5)
       RETURNING id, recorded_at`,
      [ebId, userId, lat, lng, accuracy ?? null]
    );
    return rows[0];
  }

  async getBreadcrumbs(ebId: string, since?: string) {
    const params: unknown[] = [ebId];
    let sql = `
      SELECT id, user_id,
        ST_Y(location::geometry) AS latitude,
        ST_X(location::geometry) AS longitude,
        accuracy, recorded_at
      FROM mission_gps_breadcrumbs WHERE eb_id = $1`;
    if (since) {
      sql += ' AND recorded_at >= $2';
      params.push(since);
    }
    sql += ' ORDER BY recorded_at';
    const { rows } = await query(sql, params);
    return rows;
  }

  async getLastCompletedBuilding(ebId: string, excludeBuildingId: string) {
    const { rows } = await query(
      `SELECT id, completed_at,
        ST_Y(location::geometry) AS latitude,
        ST_X(location::geometry) AS longitude
       FROM mission_buildings
       WHERE eb_id = $1 AND status = 'completed' AND id != $2 AND completed_at IS NOT NULL
       ORDER BY completed_at DESC LIMIT 1`,
      [ebId, excludeBuildingId]
    );
    return rows[0] ?? null;
  }

  async recordTravelSegment(data: {
    ebId: string;
    fromBuildingId: string | null;
    toBuildingId: string;
    userId: string;
    travelSeconds: number;
    distanceMeters?: number | null;
  }) {
    const { rows } = await query(
      `INSERT INTO mission_travel_segments
        (eb_id, from_building_id, to_building_id, user_id, travel_seconds, distance_meters)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
      [
        data.ebId,
        data.fromBuildingId,
        data.toBuildingId,
        data.userId,
        data.travelSeconds,
        data.distanceMeters ?? null,
      ]
    );
    return rows[0];
  }

  async getAverageTravelSeconds(ebId: string): Promise<number | null> {
    const { rows } = await query(
      `SELECT AVG(travel_seconds)::float AS avg_seconds
       FROM mission_travel_segments WHERE eb_id = $1`,
      [ebId]
    );
    const avg = rows[0]?.avg_seconds as number | null;
    return avg != null && !Number.isNaN(avg) ? avg : null;
  }

  async getAverageSurveySeconds(ebId: string): Promise<number | null> {
    const { rows } = await query(
      `SELECT AVG(EXTRACT(EPOCH FROM (completed_at - visited_at)))::float AS avg_seconds
       FROM mission_buildings
       WHERE eb_id = $1 AND status = 'completed'
         AND visited_at IS NOT NULL AND completed_at IS NOT NULL
         AND completed_at > visited_at`,
      [ebId]
    );
    const avg = rows[0]?.avg_seconds as number | null;
    return avg != null && !Number.isNaN(avg) ? avg : null;
  }

  async getPendingBuildings(ebId: string) {
    const { rows } = await query(
      `SELECT id, eb_id, building_number, census_house_count, building_type,
              map_x, map_y, route_sequence, status, notes, asset_id,
              visited_at, completed_at, completed_by,
              ST_Y(location::geometry) AS latitude,
              ST_X(location::geometry) AS longitude
       FROM mission_buildings
       WHERE eb_id = $1 AND status != 'completed'
       ORDER BY COALESCE(route_sequence, building_number), building_number`,
      [ebId]
    );
    return rows;
  }

  async getNextBuildingNumber(ebId: string): Promise<number> {
    const { rows } = await query(
      `SELECT COALESCE(MAX(building_number), 0) + 1 AS next_num FROM mission_buildings WHERE eb_id = $1`,
      [ebId]
    );
    return rows[0]?.next_num as number ?? 1;
  }

  async addDiscoveredBuilding(data: {
    ebId: string;
    buildingNumber: number;
    censusHouseCount: number;
    buildingType: string;
    latitude: number;
    longitude: number;
    mapX: number;
    mapY: number;
    routeSequence: number;
  }) {
    const { rows } = await query(
      `INSERT INTO mission_buildings (
        eb_id, building_number, census_house_count, building_type,
        map_x, map_y, route_sequence, location, status
      ) VALUES (
        $1, $2, $3, $4::mission_building_type, $5, $6, $7,
        ST_SetSRID(ST_MakePoint($9, $8), 4326), 'not_visited'
      ) RETURNING id, building_number`,
      [
        data.ebId,
        data.buildingNumber,
        data.censusHouseCount,
        data.buildingType,
        data.mapX,
        data.mapY,
        data.routeSequence,
        data.latitude,
        data.longitude,
      ]
    );
    return rows[0];
  }

  async addBoundaryVertex(ebId: string, lat: number, lng: number) {
    const { rows: seqRows } = await query(
      `SELECT COALESCE(MAX(sequence), 0) + 1 AS next_seq FROM mission_boundary_vertices WHERE eb_id = $1`,
      [ebId]
    );
    const sequence = seqRows[0]?.next_seq as number ?? 1;
    const { rows } = await query(
      `INSERT INTO mission_boundary_vertices (eb_id, sequence, location)
       VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326))
       RETURNING id, sequence`,
      [ebId, sequence, lat, lng]
    );
    return rows[0];
  }

  async getBoundaryVertices(ebId: string) {
    const { rows } = await query(
      `SELECT id, sequence,
        ST_Y(location::geometry) AS latitude,
        ST_X(location::geometry) AS longitude,
        recorded_at
       FROM mission_boundary_vertices WHERE eb_id = $1 ORDER BY sequence`,
      [ebId]
    );
    return rows;
  }

  async getPathWalkedMeters(ebId: string): Promise<number> {
    const { rows } = await query(
      `WITH ordered AS (
        SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
               ROW_NUMBER() OVER (ORDER BY recorded_at) AS rn
        FROM mission_gps_breadcrumbs WHERE eb_id = $1
      ),
      pairs AS (
        SELECT a.lat AS lat1, a.lng AS lng1, b.lat AS lat2, b.lng AS lng2
        FROM ordered a JOIN ordered b ON b.rn = a.rn + 1
      )
      SELECT COALESCE(SUM(
        6371000 * 2 * ASIN(SQRT(
          POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
          COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * POWER(SIN(RADIANS(lng2 - lng1) / 2), 2)
        ))
      ), 0)::float AS meters FROM pairs`,
      [ebId]
    );
    return (rows[0]?.meters as number) ?? 0;
  }

  async addDiscoveredLandmark(data: {
    ebId: string;
    name: string;
    landmarkType: string;
    latitude: number;
    longitude: number;
    mapX: number;
    mapY: number;
  }) {
    const { rows } = await query(
      `INSERT INTO mission_landmarks (eb_id, name, landmark_type, map_x, map_y, location)
       VALUES ($1, $2, $3::landmark_type, $4, $5, ST_SetSRID(ST_MakePoint($7, $6), 4326))
       RETURNING id, name`,
      [data.ebId, data.name, data.landmarkType, data.mapX, data.mapY, data.latitude, data.longitude]
    );
    return rows[0];
  }

  async getGapResolutions(ebId: string) {
    const { rows } = await query(
      `SELECT gap_fingerprint, gap_type, gap_reason, resolution, notes, resolved_at
       FROM mission_coverage_gap_resolutions WHERE eb_id = $1`,
      [ebId]
    );
    return rows;
  }

  async resolveGap(data: {
    ebId: string;
    gapFingerprint: string;
    gapType: string;
    gapReason: string;
    latitude?: number | null;
    longitude?: number | null;
    resolution: string;
    notes?: string | null;
    resolvedBy: string;
    resolvedLatitude?: number | null;
    resolvedLongitude?: number | null;
  }) {
    const { rows } = await query(
      `INSERT INTO mission_coverage_gap_resolutions (
        eb_id, gap_fingerprint, gap_type, gap_reason, latitude, longitude,
        resolution, notes, resolved_by, resolved_latitude, resolved_longitude
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      ON CONFLICT (eb_id, gap_fingerprint) DO UPDATE SET
        resolution = EXCLUDED.resolution,
        notes = EXCLUDED.notes,
        resolved_at = NOW(),
        resolved_by = EXCLUDED.resolved_by,
        resolved_latitude = EXCLUDED.resolved_latitude,
        resolved_longitude = EXCLUDED.resolved_longitude
      RETURNING *`,
      [
        data.ebId,
        data.gapFingerprint,
        data.gapType,
        data.gapReason,
        data.latitude ?? null,
        data.longitude ?? null,
        data.resolution,
        data.notes ?? null,
        data.resolvedBy,
        data.resolvedLatitude ?? null,
        data.resolvedLongitude ?? null,
      ]
    );
    return rows[0];
  }

  async supervisorSummary(projectId: string) {
    const { rows } = await query(
      `SELECT
        eb.id AS eb_id,
        eb.eb_code,
        eb.name,
        eb.status,
        eb.assigned_enumerator_id,
        u.first_name || ' ' || u.last_name AS enumerator_name,
        COUNT(mb.id)::int AS total_buildings,
        COUNT(mb.id) FILTER (WHERE mb.status = 'completed')::int AS completed_buildings,
        COUNT(mb.id) FILTER (WHERE mb.status = 'not_visited')::int AS missed_count,
        COUNT(mb.id) FILTER (WHERE mb.status = 'revisit_required')::int AS revisit_count
       FROM enumeration_blocks eb
       LEFT JOIN users u ON u.id = eb.assigned_enumerator_id
       LEFT JOIN mission_buildings mb ON mb.eb_id = eb.id
       WHERE eb.project_id = $1
       GROUP BY eb.id, u.first_name, u.last_name
       ORDER BY eb.eb_code`,
      [projectId]
    );
    return rows;
  }
}

export const missionRepository = new MissionRepository();
