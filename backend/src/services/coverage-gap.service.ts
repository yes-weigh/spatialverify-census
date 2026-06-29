import type { CoverageGapsResponse } from '../types/mission.js';
import { missionRepository } from '../repositories/mission.repository.js';
import { detectCoverageGaps, summarizeGaps, type GapResolutionStatus } from '../utils/coverage-gap-detection.js';
import { estimatePathCoveragePercent, type GpsPoint } from '../utils/serpentine-numbering.js';
import { haversineMeters } from '../utils/geo.js';
import { computeBounds } from '../utils/serpentine-numbering.js';

async function loadGapContext(ebId: string) {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return null;

  const [vertices, pathMeters, buildings, breadcrumbs, stats, resolutions] = await Promise.all([
    missionRepository.getBoundaryVertices(ebId),
    missionRepository.getPathWalkedMeters(ebId),
    missionRepository.getBuildings(ebId),
    missionRepository.getBreadcrumbs(ebId),
    missionRepository.getBuildingStats(ebId),
    missionRepository.getGapResolutions(ebId),
  ]);

  const boundaryVertices = vertices.length;
  let boundaryClosed = false;
  if (boundaryVertices >= 4) {
    const first = vertices[0];
    const last = vertices[boundaryVertices - 1];
    boundaryClosed =
      haversineMeters(
        parseFloat(String(first.latitude)),
        parseFloat(String(first.longitude)),
        parseFloat(String(last.latitude)),
        parseFloat(String(last.longitude))
      ) <= 50;
  }

  const gpsBuildings: GpsPoint[] = buildings
    .filter((b) => b.latitude != null && b.longitude != null)
    .map((b) => ({
      id: b.id as string,
      latitude: parseFloat(String(b.latitude)),
      longitude: parseFloat(String(b.longitude)),
      buildingNumber: b.building_number as number,
    }));

  const bc = breadcrumbs.map((b) => ({
    latitude: parseFloat(String(b.latitude)),
    longitude: parseFloat(String(b.longitude)),
  }));

  const allGps = [
    ...vertices.map((v) => ({ latitude: parseFloat(String(v.latitude)), longitude: parseFloat(String(v.longitude)) })),
    ...gpsBuildings,
    ...bc,
  ];
  const bounds = computeBounds(allGps.length > 0 ? allGps : [{ latitude: 10, longitude: 76 }]);
  const roadCoveragePercent = estimatePathCoveragePercent(bc, bounds);

  return {
    block,
    pathMeters,
    buildingsDiscovered: stats.total as number,
    boundaryVertices,
    boundaryClosed,
    roadCoveragePercent,
    breadcrumbs: bc,
    buildings: gpsBuildings,
    vertices: vertices.map((v) => ({
      latitude: parseFloat(String(v.latitude)),
      longitude: parseFloat(String(v.longitude)),
    })),
    layoutBoundaryLength: ((block.boundary_map as unknown[]) ?? []).length,
    resolutions: resolutions.map((r) => ({
      gap_fingerprint: r.gap_fingerprint as string,
      resolution: r.resolution as GapResolutionStatus,
      resolved_at: String(r.resolved_at),
      notes: (r.notes as string) ?? null,
    })),
  };
}

export async function buildCoverageGapsResponse(
  ebId: string,
  enumeratorLat?: number,
  enumeratorLng?: number
): Promise<CoverageGapsResponse | null> {
  const ctx = await loadGapContext(ebId);
  if (!ctx) return null;

  const gaps = detectCoverageGaps({
    pathMeters: ctx.pathMeters,
    buildingsDiscovered: ctx.buildingsDiscovered,
    boundaryVertices: ctx.boundaryVertices,
    boundaryClosed: ctx.boundaryClosed,
    roadCoveragePercent: ctx.roadCoveragePercent,
    breadcrumbs: ctx.breadcrumbs,
    buildings: ctx.buildings,
    vertices: ctx.vertices,
    layoutBoundaryLength: ctx.layoutBoundaryLength,
    resolutions: ctx.resolutions,
    enumeratorLat,
    enumeratorLng,
  });

  return {
    ebId,
    ebCode: ctx.block.eb_code as string,
    summary: summarizeGaps(gaps),
    gaps,
  };
}

export async function resolveCoverageGap(
  ebId: string,
  gapId: string,
  data: {
    resolution: GapResolutionStatus;
    notes?: string;
    gapType: string;
    gapReason: string;
    latitude?: number | null;
    longitude?: number | null;
    resolvedBy: string;
    resolvedLatitude?: number | null;
    resolvedLongitude?: number | null;
  }
) {
  return missionRepository.resolveGap({
    ebId,
    gapFingerprint: gapId,
    gapType: data.gapType,
    gapReason: data.gapReason,
    latitude: data.latitude,
    longitude: data.longitude,
    resolution: data.resolution,
    notes: data.notes ?? null,
    resolvedBy: data.resolvedBy,
    resolvedLatitude: data.resolvedLatitude,
    resolvedLongitude: data.resolvedLongitude,
  });
}
