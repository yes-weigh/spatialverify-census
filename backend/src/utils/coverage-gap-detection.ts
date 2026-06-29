import { haversineMeters } from './geo.js';
import { pointInPolygon } from './polygon-utils.js';
import {
  computeBounds,
  findUnrecordedClusters,
  findUnvisitedGridCells,
  projectToMapCoords,
  type GpsPoint,
} from './serpentine-numbering.js';

export type GapSeverity = 'high' | 'medium' | 'low';
export type GapResolutionStatus = 'building_found' | 'no_building' | 'not_accessible' | 'investigated';

export interface CoverageGapItem {
  id: string;
  type: string;
  reason: string;
  severity: GapSeverity;
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
    status: GapResolutionStatus;
    resolvedAt: string;
    notes: string | null;
  } | null;
}

export interface GapDetectionInput {
  pathMeters: number;
  buildingsDiscovered: number;
  boundaryVertices: number;
  boundaryClosed: boolean;
  roadCoveragePercent: number;
  breadcrumbs: Array<{ latitude: number; longitude: number }>;
  buildings: GpsPoint[];
  vertices: Array<{ latitude: number; longitude: number }>;
  layoutBoundaryLength: number;
  hasOfficialBoundary?: boolean;
  officialPolygon?: { type: 'Polygon'; coordinates: number[][][] };
  resolutions: Array<{
    gap_fingerprint: string;
    resolution: GapResolutionStatus;
    resolved_at: string;
    notes: string | null;
  }>;
  enumeratorLat?: number;
  enumeratorLng?: number;
}

export function gapFingerprint(type: string, reason: string, lat?: number | null, lng?: number | null): string {
  if (lat != null && lng != null) {
    return `${type}:${lat.toFixed(5)}:${lng.toFixed(5)}`;
  }
  return `${type}:${reason}`;
}

function bearingDegrees(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const lat1r = (lat1 * Math.PI) / 180;
  const lat2r = (lat2 * Math.PI) / 180;
  const y = Math.sin(dLng) * Math.cos(lat2r);
  const x = Math.cos(lat1r) * Math.sin(lat2r) - Math.sin(lat1r) * Math.cos(lat2r) * Math.cos(dLng);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

function formatDistance(meters: number): string {
  if (meters < 1000) return `${Math.round(meters)}m`;
  return `${(meters / 1000).toFixed(1)}km`;
}

function countNearbyBuildings(lat: number, lng: number, buildings: GpsPoint[], radiusMeters: number): number {
  return buildings.filter((b) => haversineMeters(lat, lng, b.latitude, b.longitude) <= radiusMeters).length;
}

function withNavigation(
  gap: Omit<CoverageGapItem, 'distanceMeters' | 'bearingDegrees' | 'distanceLabel' | 'mapX' | 'mapY'>,
  bounds: ReturnType<typeof computeBounds>,
  enumeratorLat?: number,
  enumeratorLng?: number
): CoverageGapItem {
  let distanceMeters: number | null = null;
  let bearing: number | null = null;
  let distanceLabel: string | null = null;
  let mapX: number | null = null;
  let mapY: number | null = null;

  if (gap.latitude != null && gap.longitude != null) {
    const coords = projectToMapCoords(gap.latitude, gap.longitude, bounds);
    mapX = coords.x;
    mapY = coords.y;
    if (enumeratorLat != null && enumeratorLng != null) {
      distanceMeters = haversineMeters(enumeratorLat, enumeratorLng, gap.latitude, gap.longitude);
      bearing = bearingDegrees(enumeratorLat, enumeratorLng, gap.latitude, gap.longitude);
      distanceLabel = formatDistance(distanceMeters);
    }
  }

  return { ...gap, distanceMeters, bearingDegrees: bearing, distanceLabel, mapX, mapY };
}

/** Detect suspicious areas — enumerator must prove they were investigated. */
export function detectCoverageGaps(input: GapDetectionInput): CoverageGapItem[] {
  const resolutionMap = new Map(input.resolutions.map((r) => [r.gap_fingerprint, r]));
  const raw: Array<Omit<CoverageGapItem, 'distanceMeters' | 'bearingDegrees' | 'distanceLabel' | 'mapX' | 'mapY'>> = [];

  const allGps = [
    ...input.vertices,
    ...input.buildings,
    ...input.breadcrumbs,
  ];
  const bounds = computeBounds(allGps.length > 0 ? allGps : [{ latitude: 10, longitude: 76 }]);

  // Road walked with buildings on both sides but none recorded here
  if (input.breadcrumbs.length >= 8 && input.buildings.length > 0) {
    const window = 6;
    for (let i = 0; i < input.breadcrumbs.length; i += window) {
      const slice = input.breadcrumbs.slice(i, i + window);
      const lat = slice.reduce((s, p) => s + p.latitude, 0) / slice.length;
      const lng = slice.reduce((s, p) => s + p.longitude, 0) / slice.length;
      const nearby = countNearbyBuildings(lat, lng, input.buildings, 100);
      const atPoint = countNearbyBuildings(lat, lng, input.buildings, 45);
      if (nearby >= 3 && atPoint === 0) {
        raw.push({
          id: gapFingerprint('road_without_building', 'dense_corridor', lat, lng),
          type: 'road_without_building',
          reason: 'dense_corridor',
          severity: 'high',
          title: 'Road segment without building',
          description: 'Walked road with nearby buildings on both sides — no structure recorded here',
          latitude: lat,
          longitude: lng,
          resolution: null,
        });
      }
    }
  }

  // Walked path clusters with no building
  for (const c of findUnrecordedClusters(input.breadcrumbs, input.buildings)) {
    const nearby = countNearbyBuildings(c.lat, c.lng, input.buildings, 120);
    raw.push({
      id: gapFingerprint('empty_cluster', 'walk_no_building', c.lat, c.lng),
      type: 'empty_cluster',
      reason: 'walk_no_building',
      severity: nearby >= 2 ? 'high' : 'medium',
      title: nearby >= 2 ? 'Dense area — no building recorded' : 'Walked area — no building recorded',
      description:
        nearby >= 2
          ? 'Path passed through area surrounded by buildings — confirm no structure was missed'
          : 'Walk path with no building confirmed nearby',
      latitude: c.lat,
      longitude: c.lng,
      resolution: null,
    });
  }

  // Unwalked grid cells inside boundary
  for (const cell of findUnvisitedGridCells(input.breadcrumbs, bounds)) {
    const nearbyBuildings = countNearbyBuildings(cell.lat, cell.lng, input.buildings, 80);
    raw.push({
      id: gapFingerprint('unwalked_road', `grid_${cell.cellX}_${cell.cellY}`, cell.lat, cell.lng),
      type: 'unwalked_road',
      reason: `grid_${cell.cellX}_${cell.cellY}`,
      severity: nearbyBuildings >= 2 ? 'high' : nearbyBuildings === 0 ? 'low' : 'medium',
      title: nearbyBuildings >= 2 ? 'Unwalked road near buildings' : 'Area not yet walked',
      description:
        nearbyBuildings >= 2
          ? 'Road segment near recorded buildings has not been traversed'
          : 'Block area with no walk coverage — may be open land or canal bank',
      latitude: cell.lat,
      longitude: cell.lng,
      resolution: null,
    });
  }

  // Boundary not closed — skip when official boundary is loaded
  if (!input.hasOfficialBoundary) {
    if (input.boundaryVertices > 0 && !input.boundaryClosed && input.vertices.length >= 2) {
      const first = input.vertices[0];
      const last = input.vertices[input.vertices.length - 1];
      const lat = (first.latitude + last.latitude) / 2;
      const lng = (first.longitude + last.longitude) / 2;
      raw.push({
        id: gapFingerprint('boundary_gap', 'loop_not_closed'),
        type: 'boundary_gap',
        reason: 'loop_not_closed',
        severity: 'high',
        title: 'Boundary loop not closed',
        description: 'HLB perimeter walk is open — return to start corner to close the boundary',
        latitude: lat,
        longitude: lng,
        resolution: null,
      });
    } else if (input.boundaryVertices === 0 && input.layoutBoundaryLength < 3) {
      raw.push({
        id: gapFingerprint('boundary_gap', 'no_boundary'),
        type: 'boundary_gap',
        reason: 'no_boundary',
        severity: 'high',
        title: 'No HLB boundary recorded',
        description: 'Walk the block perimeter and mark boundary corners',
        latitude: input.breadcrumbs.at(-1)?.latitude ?? null,
        longitude: input.breadcrumbs.at(-1)?.longitude ?? null,
        resolution: null,
      });
    }
  }

  if (input.pathMeters > 400 && input.buildingsDiscovered === 0) {
    const last = input.breadcrumbs.at(-1);
    raw.push({
      id: gapFingerprint('unrecorded_walk', 'walk_without_buildings'),
      type: 'unrecorded_walk',
      reason: 'walk_without_buildings',
      severity: 'high',
      title: 'Area walked — zero buildings',
      description: 'Significant walk distance with no buildings confirmed — verify each structure',
      latitude: last?.latitude ?? null,
      longitude: last?.longitude ?? null,
      resolution: null,
    });
  }

  if (input.roadCoveragePercent < 40 && input.pathMeters > 200 && input.breadcrumbs.length > 0) {
    const cell = findUnvisitedGridCells(input.breadcrumbs, bounds)[0];
    if (!cell) {
      raw.push({
        id: gapFingerprint('unwalked_road', 'low_coverage'),
        type: 'unwalked_road',
        reason: 'low_coverage',
        severity: 'medium',
        title: 'Low road coverage',
        description: `Only ${input.roadCoveragePercent}% of block area covered — walk remaining paths`,
        latitude: input.breadcrumbs[Math.floor(input.breadcrumbs.length / 2)]?.latitude ?? null,
        longitude: input.breadcrumbs[Math.floor(input.breadcrumbs.length / 2)]?.longitude ?? null,
        resolution: null,
      });
    }
  }

  // Deduplicate by id, attach resolutions, add navigation
  const seen = new Set<string>();
  const gaps: CoverageGapItem[] = [];

  for (const g of raw) {
    if (seen.has(g.id)) continue;
    if (
      input.officialPolygon &&
      g.latitude != null &&
      g.longitude != null &&
      !pointInPolygon(g.latitude, g.longitude, input.officialPolygon)
    ) {
      continue;
    }
    seen.add(g.id);

    const res = resolutionMap.get(g.id);
    const withRes: typeof g = res
      ? {
          ...g,
          resolution: {
            status: res.resolution,
            resolvedAt: new Date(res.resolved_at).toISOString(),
            notes: res.notes,
          },
        }
      : g;

    gaps.push(withNavigation(withRes, bounds, input.enumeratorLat, input.enumeratorLng));
  }

  const severityOrder = { high: 0, medium: 1, low: 2 };
  gaps.sort((a, b) => {
    if (a.resolution && !b.resolution) return 1;
    if (!a.resolution && b.resolution) return -1;
    const sd = severityOrder[a.severity] - severityOrder[b.severity];
    if (sd !== 0) return sd;
    return (a.distanceMeters ?? 99999) - (b.distanceMeters ?? 99999);
  });

  return gaps;
}

export function summarizeGaps(gaps: CoverageGapItem[]) {
  const open = gaps.filter((g) => !g.resolution);
  return {
    total: gaps.length,
    open: open.length,
    resolved: gaps.length - open.length,
    highPriority: open.filter((g) => g.severity === 'high').length,
    mediumPriority: open.filter((g) => g.severity === 'medium').length,
    lowPriority: open.filter((g) => g.severity === 'low').length,
  };
}
