export interface GeoJSONPolygon {
  type: 'Polygon';
  coordinates: number[][][];
}

export interface HlbStartPoint {
  lat: number;
  lng: number;
}

export interface HlbBoundary {
  id: string;
  ebId: string;
  hlbCode: string;
  name: string | null;
  boundaryPolygon: GeoJSONPolygon;
  areaSqMeters: number;
  northDescription?: string | null;
  southDescription?: string | null;
  eastDescription?: string | null;
  westDescription?: string | null;
  source: 'official' | 'layout_map';
  startPoint: HlbStartPoint;
  importedAt: string;
}

export interface OutsideBoundaryDiscovery {
  latitude: number;
  longitude: number;
  label: string;
  overridden: boolean;
  recordedAt: string;
}

export interface MissionBoundaryAudit {
  ebId: string;
  enumeratorId?: string | null;
  enteredBoundaryAt?: string | null;
  leftBoundaryAt?: string | null;
  startPointReachedAt?: string | null;
  discoveryStartedAt?: string | null;
  outsideBoundaryDiscoveries: OutsideBoundaryDiscovery[];
}

export interface HlbMissionPackage {
  boundary: HlbBoundary;
  ebId: string;
  ebCode: string;
  projectId: string;
  phase: 'mapping' | 'listing';
  audit: MissionBoundaryAudit | null;
}
