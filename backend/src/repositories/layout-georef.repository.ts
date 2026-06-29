import { query } from '../db/pool.js';
import type { GeoJSONPolygon } from '../types/hlb-boundary.js';
import type { GpsPoint, ImageBounds, LayoutControlPoint, LayoutGeorefSession, PotentialStructure } from '../types/layout-georef.js';

function mapRow(row: Record<string, unknown>): LayoutGeorefSession {
  return {
    id: row.id as string,
    ebId: row.eb_id as string,
    uploadedMapKey: row.uploaded_map_key as string,
    previewMapKey: row.preview_map_key as string | null,
    mimeType: row.mime_type as string,
    status: row.status as LayoutGeorefSession['status'],
    alignmentMode: (row.alignment_mode as LayoutGeorefSession['alignmentMode']) ?? 'satellite_registration',
    aiSuggestions: (row.ai_suggestions as Record<string, unknown>) ?? {},
    imageBounds: row.image_bounds as ImageBounds | null,
    gpsBoundary: (row.gps_boundary as GpsPoint[]) ?? [],
    potentialStructures: (row.potential_structures as PotentialStructure[]) ?? [],
    controlPoints: (row.control_points as LayoutControlPoint[]) ?? [],
    sketchBoundary: (row.sketch_boundary as Array<{ x: number; y: number }>) ?? [],
    affineMatrix: row.affine_matrix as number[] | null,
    boundaryPolygon: row.boundary_polygon as GeoJSONPolygon | null,
    landmarks: (row.landmarks as unknown[]) ?? [],
    roads: (row.roads as unknown[]) ?? [],
    waterBodies: (row.water_bodies as unknown[]) ?? [],
    alignmentScore: row.alignment_score as string | null,
    rmsErrorMeters: row.rms_error_meters != null ? parseFloat(String(row.rms_error_meters)) : null,
    polygonAreaSqMeters: row.polygon_area_sq_meters != null ? parseFloat(String(row.polygon_area_sq_meters)) : null,
    missionIntelligence: (row.mission_intelligence as Record<string, unknown>) ?? null,
    alignmentQualityPercent: row.alignment_quality_percent != null ? parseInt(String(row.alignment_quality_percent), 10) : null,
    createdBy: row.created_by as string | null,
    createdAt: row.created_at as string,
    finalizedAt: row.finalized_at as string | null,
  };
}

export class LayoutGeorefRepository {
  async findByEbId(ebId: string) {
    const { rows } = await query(`SELECT * FROM layout_georef_sessions WHERE eb_id = $1`, [ebId]);
    return rows[0] ? mapRow(rows[0]) : null;
  }

  async upsertUpload(data: {
    ebId: string;
    uploadedMapKey: string;
    previewMapKey?: string;
    mimeType: string;
    createdBy: string;
  }) {
    const { rows } = await query(
      `INSERT INTO layout_georef_sessions (
         eb_id, uploaded_map_key, preview_map_key, mime_type, status,
         alignment_mode, created_by, updated_at
       ) VALUES ($1, $2, $3, $4, 'uploaded', 'satellite_registration', $5, NOW())
       ON CONFLICT (eb_id) DO UPDATE SET
         uploaded_map_key = EXCLUDED.uploaded_map_key,
         preview_map_key = COALESCE(EXCLUDED.preview_map_key, layout_georef_sessions.preview_map_key),
         mime_type = EXCLUDED.mime_type,
         status = 'uploaded',
         alignment_mode = 'satellite_registration',
         updated_at = NOW()
       RETURNING *`,
      [data.ebId, data.uploadedMapKey, data.previewMapKey ?? null, data.mimeType, data.createdBy]
    );
    return mapRow(rows[0]);
  }

  async updateSession(ebId: string, patch: Partial<{
    status: string;
    alignmentMode: string;
    imageBounds: ImageBounds;
    gpsBoundary: GpsPoint[];
    potentialStructures: PotentialStructure[];
    aiSuggestions: Record<string, unknown>;
    controlPoints: LayoutControlPoint[];
    sketchBoundary: Array<{ x: number; y: number }>;
    affineMatrix: number[];
    boundaryPolygon: GeoJSONPolygon;
    landmarks: unknown[];
    roads: unknown[];
    waterBodies: unknown[];
    alignmentScore: string;
    rmsErrorMeters: number;
    polygonAreaSqMeters: number;
    missionIntelligence: Record<string, unknown>;
    alignmentQualityPercent: number;
    finalizedAt: string;
  }>) {
    const { rows } = await query(
      `UPDATE layout_georef_sessions SET
         status = COALESCE($2, status),
         alignment_mode = COALESCE($3, alignment_mode),
         image_bounds = COALESCE($4, image_bounds),
         gps_boundary = COALESCE($5, gps_boundary),
         potential_structures = COALESCE($6, potential_structures),
         ai_suggestions = COALESCE($7, ai_suggestions),
         control_points = COALESCE($8, control_points),
         sketch_boundary = COALESCE($9, sketch_boundary),
         affine_matrix = COALESCE($10, affine_matrix),
         boundary_polygon = COALESCE($11, boundary_polygon),
         landmarks = COALESCE($12, landmarks),
         roads = COALESCE($13, roads),
         water_bodies = COALESCE($14, water_bodies),
         alignment_score = COALESCE($15, alignment_score),
         rms_error_meters = COALESCE($16, rms_error_meters),
         polygon_area_sq_meters = COALESCE($17, polygon_area_sq_meters),
         mission_intelligence = COALESCE($18, mission_intelligence),
         alignment_quality_percent = COALESCE($19, alignment_quality_percent),
         finalized_at = COALESCE($20, finalized_at),
         updated_at = NOW()
       WHERE eb_id = $1 RETURNING *`,
      [
        ebId,
        patch.status ?? null,
        patch.alignmentMode ?? null,
        patch.imageBounds ? JSON.stringify(patch.imageBounds) : null,
        patch.gpsBoundary ? JSON.stringify(patch.gpsBoundary) : null,
        patch.potentialStructures ? JSON.stringify(patch.potentialStructures) : null,
        patch.aiSuggestions ? JSON.stringify(patch.aiSuggestions) : null,
        patch.controlPoints ? JSON.stringify(patch.controlPoints) : null,
        patch.sketchBoundary ? JSON.stringify(patch.sketchBoundary) : null,
        patch.affineMatrix ?? null,
        patch.boundaryPolygon ? JSON.stringify(patch.boundaryPolygon) : null,
        patch.landmarks ? JSON.stringify(patch.landmarks) : null,
        patch.roads ? JSON.stringify(patch.roads) : null,
        patch.waterBodies ? JSON.stringify(patch.waterBodies) : null,
        patch.alignmentScore ?? null,
        patch.rmsErrorMeters ?? null,
        patch.polygonAreaSqMeters ?? null,
        patch.missionIntelligence ? JSON.stringify(patch.missionIntelligence) : null,
        patch.alignmentQualityPercent ?? null,
        patch.finalizedAt ?? null,
      ]
    );
    return rows[0] ? mapRow(rows[0]) : null;
  }
}

export const layoutGeorefRepository = new LayoutGeorefRepository();
