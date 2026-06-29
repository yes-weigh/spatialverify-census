export type UserRole = 'admin' | 'supervisor' | 'field_worker';
export type AssetStatus = 'not_surveyed' | 'pending' | 'verified' | 'rejected';
export type GeometryType = 'point' | 'line' | 'polygon';
export type SyncStatus = 'pending' | 'uploading' | 'synced' | 'failed' | 'conflict';
export type HumanDecision = 'confirmed' | 'rejected' | 'edited';
export type ReconstructionPhase = 'capture' | 'sparse_point_cloud' | 'mesh' | 'gltf_export' | 'completed' | 'failed';
export type NotificationType = 'conflict' | 'approval' | 'sync' | 'assignment' | 'system';
export type AuditAction = 'create' | 'update' | 'delete' | 'login' | 'logout' | 'sync' | 'verify' | 'reject' | 'resolve_conflict';

export interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  role: UserRole;
  is_active: boolean;
  device_id: string | null;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Project {
  id: string;
  name: string;
  description: string | null;
  boundary: GeoJSON.Polygon | null;
  survey_rules: Record<string, unknown>;
  is_active: boolean;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface Asset {
  id: string;
  project_id: string;
  category_id: string | null;
  name: string;
  description: string | null;
  status: AssetStatus;
  geometry_type: GeometryType;
  location: GeoJSON.Geometry;
  altitude: number | null;
  heading: number | null;
  metadata: Record<string, unknown>;
  created_by: string | null;
  verified_by: string | null;
  verified_at: string | null;
  client_id: string | null;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface Detection {
  id: string;
  project_id: string;
  asset_id: string | null;
  session_id: string | null;
  category_label: string;
  confidence: number;
  bounding_box: { x: number; y: number; width: number; height: number };
  location: GeoJSON.Point | null;
  altitude: number | null;
  heading: number | null;
  image_id: string | null;
  ai_model: string;
  client_id: string | null;
  created_by: string | null;
  created_at: string;
}

export interface Verification {
  id: string;
  detection_id: string;
  asset_id: string | null;
  ai_prediction: string;
  confidence: number;
  human_decision: HumanDecision;
  edited_category: string | null;
  edited_location: GeoJSON.Point | null;
  notes: string | null;
  verified_by: string;
  verified_at: string;
  client_id: string | null;
}

export interface Anchor {
  id: string;
  project_id: string;
  asset_id: string | null;
  anchor_id: string;
  latitude: number;
  longitude: number;
  altitude: number | null;
  heading: number | null;
  camera_orientation: Record<string, number> | null;
  anchor_data: Record<string, unknown>;
  is_relocated: boolean;
  created_by: string | null;
  client_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface SurveySession {
  id: string;
  project_id: string;
  user_id: string;
  started_at: string;
  ended_at: string | null;
  coverage_percentage: number;
  path: GeoJSON.MultiLineString | null;
  visited_area: GeoJSON.MultiPolygon | null;
  metadata: Record<string, unknown>;
  client_id: string | null;
  sync_status: SyncStatus;
}

export interface Conflict {
  id: string;
  project_id: string;
  asset_id: string | null;
  entity_type: string;
  entity_id: string;
  submission_a: Record<string, unknown>;
  submission_b: Record<string, unknown>;
  submitted_by_a: string;
  submitted_by_b: string;
  resolution: Record<string, unknown> | null;
  resolved_by: string | null;
  resolved_at: string | null;
  status: string;
  created_at: string;
}

export interface JwtPayload {
  sub: string;
  email: string;
  role: UserRole;
  deviceId: string;
}

export interface SyncItem {
  entity_type: string;
  entity_id: string;
  client_id: string;
  operation: 'create' | 'update' | 'delete';
  payload: Record<string, unknown>;
  timestamp: string;
}

declare global {
  namespace GeoJSON {
    interface Point {
      type: 'Point';
      coordinates: [number, number];
    }
    interface LineString {
      type: 'LineString';
      coordinates: [number, number][];
    }
    interface Polygon {
      type: 'Polygon';
      coordinates: [number, number][][];
    }
    interface MultiLineString {
      type: 'MultiLineString';
      coordinates: [number, number][][];
    }
    interface MultiPolygon {
      type: 'MultiPolygon';
      coordinates: [number, number][][][];
    }
    type Geometry = Point | LineString | Polygon | MultiLineString | MultiPolygon;
  }
}
