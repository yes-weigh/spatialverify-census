import { query } from '../db/pool.js';
import type { Detection, HumanDecision, Verification } from '../types/index.js';

function rowToDetection(row: Record<string, unknown>): Detection {
  return {
    id: row.id as string,
    project_id: row.project_id as string,
    asset_id: row.asset_id as string | null,
    session_id: row.session_id as string | null,
    category_label: row.category_label as string,
    confidence: row.confidence as number,
    bounding_box: row.bounding_box as Detection['bounding_box'],
    location: row.location ? JSON.parse(row.location as string) : null,
    altitude: row.altitude as number | null,
    heading: row.heading as number | null,
    image_id: row.image_id as string | null,
    ai_model: row.ai_model as string,
    client_id: row.client_id as string | null,
    created_by: row.created_by as string | null,
    created_at: row.created_at as string,
  };
}

export class DetectionRepository {
  async create(data: {
    projectId: string;
    assetId?: string;
    sessionId?: string;
    categoryLabel: string;
    confidence: number;
    boundingBox: Detection['bounding_box'];
    location?: GeoJSON.Point;
    altitude?: number;
    heading?: number;
    imageId?: string;
    aiModel?: string;
    createdBy?: string;
    clientId?: string;
  }): Promise<Detection> {
    const { rows } = await query(
      `INSERT INTO detections (project_id, asset_id, session_id, category_label, confidence,
                               bounding_box, location, altitude, heading, image_id, ai_model, created_by, client_id)
       VALUES ($1, $2, $3, $4, $5, $6,
               ${data.location ? 'ST_SetSRID(ST_GeomFromGeoJSON($7), 4326)' : 'NULL'},
               $${data.location ? 8 : 7}, $${data.location ? 9 : 8}, $${data.location ? 10 : 9},
               $${data.location ? 11 : 10}, $${data.location ? 12 : 11}, $${data.location ? 13 : 12})
       RETURNING id, project_id, asset_id, session_id, category_label, confidence, bounding_box,
                 ST_AsGeoJSON(location) as location, altitude, heading, image_id, ai_model,
                 client_id, created_by, created_at`,
      data.location
        ? [
            data.projectId, data.assetId ?? null, data.sessionId ?? null,
            data.categoryLabel, data.confidence, JSON.stringify(data.boundingBox),
            JSON.stringify(data.location), data.altitude ?? null, data.heading ?? null,
            data.imageId ?? null, data.aiModel ?? 'yolov8', data.createdBy ?? null, data.clientId ?? null,
          ]
        : [
            data.projectId, data.assetId ?? null, data.sessionId ?? null,
            data.categoryLabel, data.confidence, JSON.stringify(data.boundingBox),
            data.altitude ?? null, data.heading ?? null,
            data.imageId ?? null, data.aiModel ?? 'yolov8', data.createdBy ?? null, data.clientId ?? null,
          ]
    );
    return rowToDetection(rows[0]);
  }

  async findById(id: string): Promise<Detection | null> {
    const { rows } = await query(
      `SELECT id, project_id, asset_id, session_id, category_label, confidence, bounding_box,
              ST_AsGeoJSON(location) as location, altitude, heading, image_id, ai_model,
              client_id, created_by, created_at
       FROM detections WHERE id = $1`,
      [id]
    );
    return rows[0] ? rowToDetection(rows[0]) : null;
  }

  async listByProject(projectId: string, sessionId?: string): Promise<Detection[]> {
    const params: unknown[] = [projectId];
    let sql = `SELECT id, project_id, asset_id, session_id, category_label, confidence, bounding_box,
                      ST_AsGeoJSON(location) as location, altitude, heading, image_id, ai_model,
                      client_id, created_by, created_at
               FROM detections WHERE project_id = $1`;
    if (sessionId) {
      sql += ' AND session_id = $2';
      params.push(sessionId);
    }
    sql += ' ORDER BY created_at DESC';
    const { rows } = await query(sql, params);
    return rows.map(rowToDetection);
  }
}

export class VerificationRepository {
  async create(data: {
    detectionId: string;
    assetId?: string;
    aiPrediction: string;
    confidence: number;
    humanDecision: HumanDecision;
    editedCategory?: string;
    editedLocation?: GeoJSON.Point;
    notes?: string;
    verifiedBy: string;
    clientId?: string;
  }): Promise<Verification> {
    const { rows } = await query(
      `INSERT INTO verifications (detection_id, asset_id, ai_prediction, confidence, human_decision,
                                  edited_category, edited_location, notes, verified_by, client_id)
       VALUES ($1, $2, $3, $4, $5, $6,
               ${data.editedLocation ? 'ST_SetSRID(ST_GeomFromGeoJSON($7), 4326)' : 'NULL'},
               $${data.editedLocation ? 8 : 7}, $${data.editedLocation ? 9 : 8}, $${data.editedLocation ? 10 : 9})
       RETURNING id, detection_id, asset_id, ai_prediction, confidence, human_decision,
                 edited_category, ST_AsGeoJSON(edited_location) as edited_location,
                 notes, verified_by, verified_at, client_id`,
      data.editedLocation
        ? [
            data.detectionId, data.assetId ?? null, data.aiPrediction, data.confidence,
            data.humanDecision, data.editedCategory ?? null, JSON.stringify(data.editedLocation),
            data.notes ?? null, data.verifiedBy, data.clientId ?? null,
          ]
        : [
            data.detectionId, data.assetId ?? null, data.aiPrediction, data.confidence,
            data.humanDecision, data.editedCategory ?? null,
            data.notes ?? null, data.verifiedBy, data.clientId ?? null,
          ]
    );
    const row = rows[0];
    return {
      id: row.id,
      detection_id: row.detection_id,
      asset_id: row.asset_id,
      ai_prediction: row.ai_prediction,
      confidence: row.confidence,
      human_decision: row.human_decision,
      edited_category: row.edited_category,
      edited_location: row.edited_location ? JSON.parse(row.edited_location) : null,
      notes: row.notes,
      verified_by: row.verified_by,
      verified_at: row.verified_at,
      client_id: row.client_id,
    };
  }

  async findByDetection(detectionId: string): Promise<Verification[]> {
    const { rows } = await query(
      `SELECT id, detection_id, asset_id, ai_prediction, confidence, human_decision,
              edited_category, ST_AsGeoJSON(edited_location) as edited_location,
              notes, verified_by, verified_at, client_id
       FROM verifications WHERE detection_id = $1`,
      [detectionId]
    );
    return rows.map((row) => ({
      id: row.id as string,
      detection_id: row.detection_id as string,
      asset_id: row.asset_id as string | null,
      ai_prediction: row.ai_prediction as string,
      confidence: row.confidence as number,
      human_decision: row.human_decision as HumanDecision,
      edited_category: row.edited_category as string | null,
      edited_location: row.edited_location ? JSON.parse(row.edited_location as string) : null,
      notes: row.notes as string | null,
      verified_by: row.verified_by as string,
      verified_at: row.verified_at as string,
      client_id: row.client_id as string | null,
    }));
  }
}

export const detectionRepository = new DetectionRepository();
export const verificationRepository = new VerificationRepository();
