import { query } from '../db/pool.js';
import type { Anchor, Conflict, SurveySession, SyncStatus } from '../types/index.js';

export class AnchorRepository {
  async create(data: {
    projectId: string;
    assetId?: string;
    anchorId: string;
    latitude: number;
    longitude: number;
    altitude?: number;
    heading?: number;
    cameraOrientation?: Record<string, number>;
    anchorData?: Record<string, unknown>;
    createdBy?: string;
    clientId?: string;
  }): Promise<Anchor> {
    const { rows } = await query(
      `INSERT INTO anchors (project_id, asset_id, anchor_id, latitude, longitude, altitude,
                            heading, camera_orientation, anchor_data, created_by, client_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING *`,
      [
        data.projectId, data.assetId ?? null, data.anchorId,
        data.latitude, data.longitude, data.altitude ?? null,
        data.heading ?? null,
        data.cameraOrientation ? JSON.stringify(data.cameraOrientation) : null,
        JSON.stringify(data.anchorData ?? {}),
        data.createdBy ?? null, data.clientId ?? null,
      ]
    );
    return rows[0] as Anchor;
  }

  async relocate(id: string, data: {
    latitude: number;
    longitude: number;
    altitude?: number;
    heading?: number;
    cameraOrientation?: Record<string, number>;
    anchorData?: Record<string, unknown>;
  }): Promise<Anchor | null> {
    const { rows } = await query(
      `UPDATE anchors SET latitude = $1, longitude = $2, altitude = $3, heading = $4,
                          camera_orientation = $5, anchor_data = $6, is_relocated = true
       WHERE id = $7 RETURNING *`,
      [
        data.latitude, data.longitude, data.altitude ?? null, data.heading ?? null,
        data.cameraOrientation ? JSON.stringify(data.cameraOrientation) : null,
        JSON.stringify(data.anchorData ?? {}), id,
      ]
    );
    return (rows[0] as Anchor) ?? null;
  }

  async listByProject(projectId: string): Promise<Anchor[]> {
    const { rows } = await query('SELECT * FROM anchors WHERE project_id = $1', [projectId]);
    return rows as Anchor[];
  }

  async findByAnchorId(anchorId: string): Promise<Anchor | null> {
    const { rows } = await query('SELECT * FROM anchors WHERE anchor_id = $1', [anchorId]);
    return (rows[0] as Anchor) ?? null;
  }
}

export class SurveySessionRepository {
  async create(data: {
    projectId: string;
    userId: string;
    clientId?: string;
  }): Promise<SurveySession> {
    const { rows } = await query(
      `INSERT INTO survey_sessions (project_id, user_id, client_id)
       VALUES ($1, $2, $3)
       RETURNING id, project_id, user_id, started_at, ended_at, coverage_percentage,
                 ST_AsGeoJSON(path) as path, ST_AsGeoJSON(visited_area) as visited_area,
                 metadata, client_id, sync_status`,
      [data.projectId, data.userId, data.clientId ?? null]
    );
    return this.parseSession(rows[0]);
  }

  async updateCoverage(
    id: string,
    coveragePercentage: number,
    path?: GeoJSON.MultiLineString,
    visitedArea?: GeoJSON.MultiPolygon
  ): Promise<SurveySession | null> {
    const sets = ['coverage_percentage = $1'];
    const params: unknown[] = [coveragePercentage];
    let idx = 2;

    if (path) {
      sets.push(`path = ST_SetSRID(ST_GeomFromGeoJSON($${idx++}), 4326)`);
      params.push(JSON.stringify(path));
    }
    if (visitedArea) {
      sets.push(`visited_area = ST_SetSRID(ST_GeomFromGeoJSON($${idx++}), 4326)`);
      params.push(JSON.stringify(visitedArea));
    }
    params.push(id);

    const { rows } = await query(
      `UPDATE survey_sessions SET ${sets.join(', ')} WHERE id = $${idx}
       RETURNING id, project_id, user_id, started_at, ended_at, coverage_percentage,
                 ST_AsGeoJSON(path) as path, ST_AsGeoJSON(visited_area) as visited_area,
                 metadata, client_id, sync_status`,
      params
    );
    return rows[0] ? this.parseSession(rows[0]) : null;
  }

  async endSession(id: string): Promise<SurveySession | null> {
    const { rows } = await query(
      `UPDATE survey_sessions SET ended_at = NOW() WHERE id = $1
       RETURNING id, project_id, user_id, started_at, ended_at, coverage_percentage,
                 ST_AsGeoJSON(path) as path, ST_AsGeoJSON(visited_area) as visited_area,
                 metadata, client_id, sync_status`,
      [id]
    );
    return rows[0] ? this.parseSession(rows[0]) : null;
  }

  async findActive(projectId: string, userId: string): Promise<SurveySession | null> {
    const { rows } = await query(
      `SELECT id, project_id, user_id, started_at, ended_at, coverage_percentage,
              ST_AsGeoJSON(path) as path, ST_AsGeoJSON(visited_area) as visited_area,
              metadata, client_id, sync_status
       FROM survey_sessions
       WHERE project_id = $1 AND user_id = $2 AND ended_at IS NULL
       ORDER BY started_at DESC LIMIT 1`,
      [projectId, userId]
    );
    return rows[0] ? this.parseSession(rows[0]) : null;
  }

  private parseSession(row: Record<string, unknown>): SurveySession {
    return {
      id: row.id as string,
      project_id: row.project_id as string,
      user_id: row.user_id as string,
      started_at: row.started_at as string,
      ended_at: row.ended_at as string | null,
      coverage_percentage: row.coverage_percentage as number,
      path: row.path ? JSON.parse(row.path as string) : null,
      visited_area: row.visited_area ? JSON.parse(row.visited_area as string) : null,
      metadata: row.metadata as Record<string, unknown>,
      client_id: row.client_id as string | null,
      sync_status: row.sync_status as SyncStatus,
    };
  }
}

export class ConflictRepository {
  async create(data: {
    projectId: string;
    assetId?: string;
    entityType: string;
    entityId: string;
    submissionA: Record<string, unknown>;
    submissionB: Record<string, unknown>;
    submittedByA: string;
    submittedByB: string;
  }): Promise<Conflict> {
    const { rows } = await query(
      `INSERT INTO conflicts (project_id, asset_id, entity_type, entity_id,
                              submission_a, submission_b, submitted_by_a, submitted_by_b)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [
        data.projectId, data.assetId ?? null, data.entityType, data.entityId,
        JSON.stringify(data.submissionA), JSON.stringify(data.submissionB),
        data.submittedByA, data.submittedByB,
      ]
    );
    return rows[0] as Conflict;
  }

  async listOpen(projectId?: string): Promise<Conflict[]> {
    const params: unknown[] = [];
    let sql = "SELECT * FROM conflicts WHERE status = 'open'";
    if (projectId) {
      sql += ' AND project_id = $1';
      params.push(projectId);
    }
    sql += ' ORDER BY created_at DESC';
    const { rows } = await query(sql, params);
    return rows as Conflict[];
  }

  async resolve(
    id: string,
    resolution: Record<string, unknown>,
    resolvedBy: string
  ): Promise<Conflict | null> {
    const { rows } = await query(
      `UPDATE conflicts SET resolution = $1, resolved_by = $2, resolved_at = NOW(), status = 'resolved'
       WHERE id = $3 RETURNING *`,
      [JSON.stringify(resolution), resolvedBy, id]
    );
    return (rows[0] as Conflict) ?? null;
  }
}

export class SyncQueueRepository {
  async enqueue(data: {
    userId: string;
    deviceId: string;
    entityType: string;
    entityId: string;
    clientId: string;
    operation: string;
    payload: Record<string, unknown>;
  }) {
    const { rows } = await query(
      `INSERT INTO sync_queue (user_id, device_id, entity_type, entity_id, client_id, operation, payload)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [
        data.userId, data.deviceId, data.entityType, data.entityId,
        data.clientId, data.operation, JSON.stringify(data.payload),
      ]
    );
    return rows[0];
  }

  async updateStatus(id: string, status: SyncStatus, errorMessage?: string) {
    await query(
      `UPDATE sync_queue SET status = $1, error_message = $2,
                             synced_at = CASE WHEN $1 = 'synced' THEN NOW() ELSE synced_at END
       WHERE id = $3`,
      [status, errorMessage ?? null, id]
    );
  }

  async getPending(userId: string, deviceId: string) {
    const { rows } = await query(
      `SELECT * FROM sync_queue WHERE user_id = $1 AND device_id = $2 AND status IN ('pending', 'failed')
       ORDER BY created_at ASC`,
      [userId, deviceId]
    );
    return rows;
  }
}

export class AuditLogRepository {
  async log(data: {
    userId?: string;
    action: string;
    entityType?: string;
    entityId?: string;
    details?: Record<string, unknown>;
    ipAddress?: string;
    userAgent?: string;
  }) {
    await query(
      `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details, ip_address, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        data.userId ?? null, data.action, data.entityType ?? null, data.entityId ?? null,
        JSON.stringify(data.details ?? {}), data.ipAddress ?? null, data.userAgent ?? null,
      ]
    );
  }
}

export class NotificationRepository {
  async create(data: {
    userId: string;
    type: string;
    title: string;
    body: string;
    data?: Record<string, unknown>;
  }) {
    const { rows } = await query(
      `INSERT INTO notifications (user_id, type, title, body, data) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [data.userId, data.type, data.title, data.body, JSON.stringify(data.data ?? {})]
    );
    return rows[0];
  }

  async listUnread(userId: string) {
    const { rows } = await query(
      'SELECT * FROM notifications WHERE user_id = $1 AND is_read = false ORDER BY created_at DESC',
      [userId]
    );
    return rows;
  }

  async markRead(id: string, userId: string) {
    await query('UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2', [id, userId]);
  }
}

export const anchorRepository = new AnchorRepository();
export const surveySessionRepository = new SurveySessionRepository();
export const conflictRepository = new ConflictRepository();
export const syncQueueRepository = new SyncQueueRepository();
export const auditLogRepository = new AuditLogRepository();
export const notificationRepository = new NotificationRepository();
