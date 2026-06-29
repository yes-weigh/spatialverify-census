export type ViewType = 'front' | 'left' | 'right' | 'rear' | 'far' | 'unknown';
export type IdentityVerdict = 'same_asset' | 'possible_match' | 'new_asset';
export type IdentityResolutionStatus = 'pending' | 'confirmed' | 'rejected' | 'auto_linked';

export interface AssetObservation {
  id: string;
  project_id: string;
  asset_id: string | null;
  detection_id: string | null;
  image_id: string | null;
  latitude: number;
  longitude: number;
  altitude: number | null;
  accuracy: number | null;
  vertical_accuracy: number | null;
  heading: number | null;
  bearing_accuracy: number | null;
  view_type: ViewType;
  category_label: string | null;
  weather: string | null;
  lighting: string | null;
  model_name: string;
  device_model: string | null;
  camera_fov: number | null;
  camera_resolution: string | null;
  captured_by: string | null;
  captured_at: string;
  client_id: string | null;
}

export interface GpsCluster {
  centroid_lat: number;
  centroid_lng: number;
  variance_m2: number;
  radius_m: number;
  observation_count: number;
}

export interface HeadingProfile {
  mean: number | null;
  variance: number | null;
}

export interface ViewScore {
  view_type: ViewType;
  embedding_score: number;
  observation_id: string;
  captured_at: string;
}

export interface AssetFingerprint {
  asset_id: string;
  asset_name: string;
  category_label: string | null;
  gps_cluster: GpsCluster | null;
  heading_profile: HeadingProfile;
  view_scores: ViewScore[];
  best_embedding_score: number;
  best_view_type: ViewType | null;
  observation_count: number;
  last_observation_at: string | null;
  visual_drift_score: number | null;
}

export interface IdentityCandidate {
  asset_id: string;
  asset_name: string;
  category_label: string | null;
  gps_score: number;
  embedding_score: number;
  category_score: number;
  heading_score: number;
  final_confidence: number;
  distance_meters: number;
  view_scores?: ViewScore[];
  best_view_type?: ViewType | null;
  gps_cluster?: GpsCluster | null;
  inside_cluster?: boolean;
  visual_drift?: number | null;
  last_seen_at?: string | null;
}

export interface ConfidenceExplanation {
  gps: number;
  embedding: number;
  category: number;
  heading: number;
  gps_accuracy_factor?: number;
  inside_cluster?: boolean;
  best_view?: ViewType | null;
  view_breakdown?: ViewScore[];
  cluster_radius_m?: number;
  distance_to_centroid_m?: number;
  visual_drift?: number | null;
  last_seen_at?: string | null;
  summary: string;
}

export interface TemporalDriftResult {
  asset_id: string;
  drift_score: number;
  earliest_observation: string;
  latest_observation: string;
  observation_pairs: number;
  interpretation: 'stable' | 'moderate_change' | 'significant_change';
}

export interface ResolveIdentityInput {
  projectId: string;
  categoryLabel: string;
  latitude: number;
  longitude: number;
  heading?: number;
  embedding: number[];
  accuracy?: number;
  verticalAccuracy?: number;
  bearingAccuracy?: number;
  viewType?: ViewType;
  weather?: string;
  lighting?: string;
  detectionId?: string;
  imageId?: string;
  radiusMeters?: number;
  deviceModel?: string;
  cameraFov?: number;
  cameraResolution?: string;
  createdBy?: string;
  clientId?: string;
}

export interface ResolveIdentityResult {
  resolutionId: string;
  verdict: IdentityVerdict;
  matchedAssetId: string | null;
  finalConfidence: number;
  scores: {
    gps: number;
    embedding: number;
    category: number;
    heading: number;
  };
  explanation: ConfidenceExplanation;
  candidates: IdentityCandidate[];
  requiresReview: boolean;
  conflictId?: string;
}

export interface StoreObservationInput {
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
}

export const EMBEDDING_DIMENSION = 1280;

export const IDENTITY_WEIGHTS = {
  gps: 0.25,
  embedding: 0.50,
  category: 0.15,
  heading: 0.10,
} as const;

export const IDENTITY_THRESHOLDS = {
  sameAsset: {
    final: 0.85,
    embedding: 0.80,
    gps: 0.55,
  },
  possibleMatch: {
    final: 0.55,
    embedding: 0.65,
    gps: 0.40,
  },
  gpsMaxDistanceMeters: 30,
  gpsDecayScaleMeters: 10,
  searchRadiusMeters: 50,
  /** Phase 1: max geo candidates before vector ranking */
  geoCandidateLimit: 500,
  /** Final vector-ranked results returned to scoring engine */
  observationSearchLimit: 30,
  /** Geohash precision for coarse bucket filter (~153m at precision 7) */
  geohashPrecision: 7,
  driftStable: 0.15,
  driftModerate: 0.35,
} as const;

// Legacy types kept for backward compatibility
export interface AssetEmbedding {
  id: string;
  project_id: string;
  asset_id: string;
  image_id: string | null;
  detection_id: string | null;
  model_name: string;
  category_label: string | null;
  heading: number | null;
  captured_by: string | null;
  client_id: string | null;
  created_at: string;
}

export interface IdentityResolution {
  id: string;
  project_id: string;
  detection_id: string | null;
  query_category: string;
  matched_asset_id: string | null;
  verdict: IdentityVerdict;
  gps_score: number;
  embedding_score: number;
  category_score: number;
  heading_score: number;
  final_confidence: number;
  candidate_scores: IdentityCandidate[];
  resolution_status: IdentityResolutionStatus;
  resolved_by: string | null;
  resolved_at: string | null;
  conflict_id: string | null;
  created_at: string;
}
