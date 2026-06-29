export type EbStatus = 'draft' | 'published' | 'archived';

export type MissionBuildingType =
  | 'pucca_residential'
  | 'non_residential_pucca'
  | 'kutcha_residential'
  | 'kutcha_non_residential';

export type MissionBuildingStatus =
  | 'not_visited'
  | 'visited'
  | 'completed'
  | 'revisit_required';

export type LandmarkType =
  | 'school'
  | 'temple'
  | 'mosque'
  | 'church'
  | 'hospital'
  | 'panchayat_office'
  | 'park'
  | 'pond'
  | 'river'
  | 'other';

export interface MapPoint {
  x: number;
  y: number;
}

export interface EnumerationBlock {
  id: string;
  project_id: string;
  eb_code: string;
  name: string | null;
  status: EbStatus;
  layout_image_key: string | null;
  layout_image_mime: string | null;
  boundary_map: MapPoint[];
  north_bearing: number;
  route_building_ids: string[];
  assigned_enumerator_id: string | null;
  created_by: string | null;
  published_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface MissionBuilding {
  id: string;
  eb_id: string;
  building_number: number;
  census_house_count: number;
  building_type: MissionBuildingType;
  map_x: number;
  map_y: number;
  latitude?: number | null;
  longitude?: number | null;
  route_sequence: number | null;
  status: MissionBuildingStatus;
  notes: string | null;
  asset_id: string | null;
  visited_at: string | null;
  completed_at: string | null;
  completed_by: string | null;
}

export interface MissionLandmark {
  id: string;
  eb_id: string;
  name: string;
  landmark_type: LandmarkType;
  map_x: number;
  map_y: number;
}

export interface MissionDashboard {
  ebId: string;
  ebCode: string;
  ebName: string | null;
  status: EbStatus;
  totalBuildings: number;
  completedBuildings: number;
  visitedBuildings: number;
  revisitRequired: number;
  remainingBuildings: number;
  progressPercent: number;
  nextBuilding: MissionBuilding | null;
  nextBuildingStrategy?: 'nearest' | 'route';
  layoutImageUrl: string | null;
}

export interface DayReview {
  ebId: string;
  ebCode: string;
  progressPercent: number;
  completedBuildings: number;
  remainingBuildings: number;
  remainingBuildingNumbers: number[];
  estimatedRemainingMinutes: number;
  avgMinutesPerBuilding: number;
}

/** HLB ground-truth mapping phase — before house list exists. */
export interface DiscoveryStatus {
  ebId: string;
  ebCode: string;
  phase: 'mapping' | 'listing';
  boundaryCoveragePercent: number;
  roadCoveragePercent: number;
  pathWalkedMeters: number;
  pathWalkedLabel: string;
  walkingTimeMinutes: number;
  walkingTimeLabel: string;
  buildingsDiscovered: number;
  landmarksDiscovered: number;
  boundaryVertices: number;
  boundaryClosed: boolean;
  suggestedNextBuildingNumber: number;
  suggestedNextLabel: string;
  numberingIssues: Array<{
    buildingId: string;
    buildingNumber: number;
    expectedNumber: number;
    expectedLabel: string;
  }>;
  zeroExclusionWarnings: Array<{ reason: string; description: string; severity: 'high' | 'medium' | 'low' }>;
  gapSummary: {
    total: number;
    open: number;
    resolved: number;
    highPriority: number;
    mediumPriority: number;
    lowPriority: number;
  };
  coverageGaps: Array<{
    id: string;
    type: string;
    reason: string;
    severity: 'high' | 'medium' | 'low';
    title: string;
    description: string;
    latitude?: number;
    longitude?: number;
    distanceMeters?: number;
    distanceLabel?: string;
    resolution?: { status: string; resolvedAt: string } | null;
  }>;
}

export interface CoverageGapsResponse {
  ebId: string;
  ebCode: string;
  summary: {
    total: number;
    open: number;
    resolved: number;
    highPriority: number;
    mediumPriority: number;
    lowPriority: number;
  };
  gaps: Array<{
    id: string;
    type: string;
    reason: string;
    severity: 'high' | 'medium' | 'low';
    title: string;
    description: string;
    latitude: number | null;
    longitude: number | null;
    mapX: number | null;
    mapY: number | null;
    distanceMeters: number | null;
    bearingDegrees: number | null;
    distanceLabel: string | null;
    resolution: {
      status: 'building_found' | 'no_building' | 'not_accessible' | 'investigated';
      resolvedAt: string;
      notes: string | null;
    } | null;
  }>;
}

export interface CoverageAnalysis {
  ebId: string;
  totalBuildings: number;
  notVisitedBuildings: MissionBuilding[];
  revisitBuildings: MissionBuilding[];
  breadcrumbCount: number;
  potentiallyMissedAreas: Array<{
    reason: string;
    buildingIds?: string[];
    description: string;
  }>;
  coveragePercent: number;
}

export interface SupervisorMissionSummary {
  projectId: string;
  blocks: Array<{
    ebId: string;
    ebCode: string;
    name: string | null;
    status: EbStatus;
    assignedEnumeratorId: string | null;
    assignedEnumeratorName: string | null;
    totalBuildings: number;
    completedBuildings: number;
    progressPercent: number;
    missedCount: number;
    revisitCount: number;
  }>;
}

export interface SaveMissionPlanInput {
  boundaryMap: MapPoint[];
  northBearing?: number;
  routeBuildingIds?: string[];
  buildings: Array<{
    id?: string;
    buildingNumber: number;
    censusHouseCount: number;
    buildingType: MissionBuildingType;
    mapX: number;
    mapY: number;
    latitude?: number;
    longitude?: number;
    routeSequence?: number;
  }>;
  landmarks: Array<{
    id?: string;
    name: string;
    landmarkType: LandmarkType;
    mapX: number;
    mapY: number;
  }>;
}
