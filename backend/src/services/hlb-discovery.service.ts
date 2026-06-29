import type { DiscoveryStatus } from '../types/mission.js';
import { missionRepository } from '../repositories/mission.repository.js';
import { haversineMeters } from '../utils/geo.js';
import { detectCoverageGaps, summarizeGaps } from '../utils/coverage-gap-detection.js';
import {
  computeBounds,
  detectNumberingIssues,
  estimatePathCoveragePercent,
  formatCn,
  projectToMapCoords,
  serpentineOrder,
  suggestSerpentineNumber,
  type GpsPoint,
} from '../utils/serpentine-numbering.js';
export async function buildDiscoveryStatus(ebId: string): Promise<DiscoveryStatus | null> {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return null;

  const [stats, landmarks, vertices, pathMeters, buildings, breadcrumbs, resolutions] = await Promise.all([
    missionRepository.getBuildingStats(ebId),
    missionRepository.getLandmarks(ebId),
    missionRepository.getBoundaryVertices(ebId),
    missionRepository.getPathWalkedMeters(ebId),
    missionRepository.getBuildings(ebId),
    missionRepository.getBreadcrumbs(ebId),
    missionRepository.getGapResolutions(ebId),
  ]);

  const buildingsDiscovered = stats.total as number;
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

  const layoutBoundary = (block.boundary_map as Array<{ x: number; y: number }>) ?? [];
  let boundaryCoveragePercent = 0;
  if (boundaryClosed) boundaryCoveragePercent = 100;
  else if (boundaryVertices >= 3) boundaryCoveragePercent = Math.min(90, Math.round((boundaryVertices / 12) * 100));
  else if (layoutBoundary.length >= 3) boundaryCoveragePercent = Math.min(80, Math.round((layoutBoundary.length / 12) * 100));

  const phase: DiscoveryStatus['phase'] =
    block.status === 'published' && buildingsDiscovered > 0 ? 'listing' : 'mapping';

  const gpsBuildings: GpsPoint[] = buildings
    .filter((b) => b.latitude != null && b.longitude != null)
    .map((b) => ({
      id: b.id as string,
      latitude: parseFloat(String(b.latitude)),
      longitude: parseFloat(String(b.longitude)),
      buildingNumber: b.building_number as number,
    }));

  const suggestedNext = await missionRepository.getNextBuildingNumber(ebId);
  const numberingIssues = detectNumberingIssues(gpsBuildings);

  const allGps = [
    ...vertices.map((v) => ({ latitude: parseFloat(String(v.latitude)), longitude: parseFloat(String(v.longitude)) })),
    ...gpsBuildings,
    ...breadcrumbs.map((b) => ({ latitude: parseFloat(String(b.latitude)), longitude: parseFloat(String(b.longitude)) })),
  ];
  const bounds = computeBounds(allGps.length > 0 ? allGps : [{ latitude: 10, longitude: 76 }]);
  const roadCoveragePercent = estimatePathCoveragePercent(
    breadcrumbs.map((b) => ({ latitude: parseFloat(String(b.latitude)), longitude: parseFloat(String(b.longitude)) })),
    bounds
  );

  let walkingTimeMinutes = 0;
  if (breadcrumbs.length >= 2) {
    const first = new Date(breadcrumbs[0].recorded_at as string).getTime();
    const last = new Date(breadcrumbs[breadcrumbs.length - 1].recorded_at as string).getTime();
    walkingTimeMinutes = Math.max(0, Math.round((last - first) / 60000));
  }

  const warnings: DiscoveryStatus['zeroExclusionWarnings'] = [];

  const bc = breadcrumbs.map((b) => ({
    latitude: parseFloat(String(b.latitude)),
    longitude: parseFloat(String(b.longitude)),
  }));

  const allGaps = detectCoverageGaps({
    pathMeters,
    buildingsDiscovered,
    boundaryVertices,
    boundaryClosed,
    roadCoveragePercent,
    breadcrumbs: bc,
    buildings: gpsBuildings,
    vertices: vertices.map((v) => ({
      latitude: parseFloat(String(v.latitude)),
      longitude: parseFloat(String(v.longitude)),
    })),
    layoutBoundaryLength: layoutBoundary.length,
    resolutions: resolutions.map((r) => ({
      gap_fingerprint: r.gap_fingerprint as string,
      resolution: r.resolution as 'building_found' | 'no_building' | 'not_accessible' | 'investigated',
      resolved_at: String(r.resolved_at),
      notes: (r.notes as string) ?? null,
    })),
  });

  const gapSummary = summarizeGaps(allGaps);
  const openGaps = allGaps.filter((g) => !g.resolution);

  for (const g of openGaps.filter((g) => g.severity === 'high').slice(0, 3)) {
    warnings.push({ reason: g.type, description: g.description, severity: g.severity });
  }

  if (numberingIssues.length > 0) {
    warnings.push({ reason: 'numbering_mismatch', description: `${numberingIssues.length} building(s) out of NW→SE serpentine order`, severity: 'medium' });
  }
  if (phase === 'listing' && (stats.not_visited as number) > 0) {
    warnings.push({ reason: 'unlisted_buildings', description: `${stats.not_visited} building(s) not yet listed`, severity: 'high' });
  }

  const walkingTimeLabel =
    walkingTimeMinutes >= 60 ? `${Math.floor(walkingTimeMinutes / 60)}h ${walkingTimeMinutes % 60}m` : walkingTimeMinutes > 0 ? `${walkingTimeMinutes}m` : '—';

  return {
    ebId,
    ebCode: block.eb_code as string,
    phase,
    boundaryCoveragePercent,
    roadCoveragePercent,
    pathWalkedMeters: Math.round(pathMeters),
    pathWalkedLabel: pathMeters >= 1000 ? `${(pathMeters / 1000).toFixed(1)} km walked` : `${Math.round(pathMeters)} m walked`,
    walkingTimeMinutes,
    walkingTimeLabel,
    buildingsDiscovered,
    landmarksDiscovered: landmarks.length,
    boundaryVertices,
    boundaryClosed,
    suggestedNextBuildingNumber: suggestedNext,
    suggestedNextLabel: formatCn(suggestedNext),
    numberingIssues: numberingIssues.map((i) => ({
      buildingId: i.buildingId,
      buildingNumber: i.buildingNumber,
      expectedNumber: i.expectedNumber,
      expectedLabel: formatCn(i.expectedNumber),
    })),
    zeroExclusionWarnings: warnings,
    gapSummary,
    coverageGaps: openGaps.slice(0, 8).map((g) => ({
      id: g.id,
      type: g.type,
      reason: g.reason,
      severity: g.severity,
      title: g.title,
      description: g.description,
      latitude: g.latitude ?? undefined,
      longitude: g.longitude ?? undefined,
      distanceMeters: g.distanceMeters ?? undefined,
      distanceLabel: g.distanceLabel ?? undefined,
      resolution: g.resolution,
    })),
  };
}

export async function getDraftMapPayload(ebId: string) {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return null;

  const [buildings, landmarks, vertices, breadcrumbs] = await Promise.all([
    missionRepository.getBuildings(ebId),
    missionRepository.getLandmarks(ebId),
    missionRepository.getBoundaryVertices(ebId),
    missionRepository.getBreadcrumbs(ebId),
  ]);

  const allPoints = [
    ...vertices.map((v) => ({ latitude: parseFloat(String(v.latitude)), longitude: parseFloat(String(v.longitude)) })),
    ...buildings.filter((b) => b.latitude != null).map((b) => ({ latitude: parseFloat(String(b.latitude)), longitude: parseFloat(String(b.longitude)) })),
  ];
  const bounds = computeBounds(allPoints.length > 0 ? allPoints : [{ latitude: 10, longitude: 76 }]);

  const boundaryPath =
    vertices.length >= 2
      ? vertices.map((v) => projectToMapCoords(parseFloat(String(v.latitude)), parseFloat(String(v.longitude)), bounds))
      : (block.boundary_map as Array<{ x: number; y: number }>) ?? [];

  return {
    ebId,
    ebCode: block.eb_code,
    northUp: true,
    boundary: boundaryPath,
    boundaryClosed: vertices.length >= 4,
    buildings: buildings.map((b) => {
      const hasGps = b.latitude != null && b.longitude != null;
      const coords = hasGps
        ? projectToMapCoords(parseFloat(String(b.latitude)), parseFloat(String(b.longitude)), bounds)
        : { x: b.map_x as number, y: b.map_y as number };
      return {
        id: b.id,
        buildingNumber: b.building_number,
        censusHouseCount: b.census_house_count,
        buildingType: b.building_type,
        mapX: coords.x,
        mapY: coords.y,
        label: `${b.building_number} (${b.census_house_count})`,
      };
    }),
    landmarks: landmarks.map((l) => ({ name: l.name, type: l.landmark_type, mapX: l.map_x, mapY: l.map_y })),
    walkPath: breadcrumbs
      .filter((_, i) => i % Math.max(1, Math.floor(breadcrumbs.length / 200)) === 0)
      .map((b) => projectToMapCoords(parseFloat(String(b.latitude)), parseFloat(String(b.longitude)), bounds)),
    serpentineOrder: serpentineOrder(
      buildings.filter((b) => b.latitude != null).map((b) => ({
        id: b.id as string,
        latitude: parseFloat(String(b.latitude)),
        longitude: parseFloat(String(b.longitude)),
        buildingNumber: b.building_number as number,
      }))
    ).map((b, i) => ({ buildingId: b.id, sequence: i + 1, label: formatCn(i + 1) })),
  };
}

export async function suggestNumberAtGps(ebId: string, lat: number, lng: number): Promise<number> {
  const buildings = await missionRepository.getBuildings(ebId);
  const gpsBuildings: GpsPoint[] = buildings
    .filter((b) => b.latitude != null && b.longitude != null)
    .map((b) => ({
      id: b.id as string,
      latitude: parseFloat(String(b.latitude)),
      longitude: parseFloat(String(b.longitude)),
      buildingNumber: b.building_number as number,
    }));
  return suggestSerpentineNumber(lat, lng, gpsBuildings);
}
