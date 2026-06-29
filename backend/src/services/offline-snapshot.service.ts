import { missionRepository } from '../repositories/mission.repository.js';
import { hlbBoundaryRepository } from '../repositories/hlb-boundary.repository.js';
import { layoutGeorefRepository } from '../repositories/layout-georef.repository.js';

/** Raw HLB entities for mobile offline cache hydration — not a workflow endpoint. */
export async function getOfflineSnapshot(ebId: string) {
  const block = await missionRepository.findBlockById(ebId);
  if (!block) return null;

  const [buildings, landmarks, vertices, breadcrumbs, resolutions, stats, officialBoundary, audit, layoutGeoref] = await Promise.all([
    missionRepository.getBuildings(ebId),
    missionRepository.getLandmarks(ebId),
    missionRepository.getBoundaryVertices(ebId),
    missionRepository.getBreadcrumbs(ebId),
    missionRepository.getGapResolutions(ebId),
    missionRepository.getBuildingStats(ebId),
    hlbBoundaryRepository.findByEbId(ebId),
    hlbBoundaryRepository.getAudit(ebId),
    layoutGeorefRepository.findByEbId(ebId),
  ]);

  const buildingsDiscovered = stats.total as number;
  const phase =
    block.status === 'published' && buildingsDiscovered > 0 ? 'listing' : 'mapping';

  return {
    ebId,
    ebCode: block.eb_code,
    projectId: block.project_id,
    blockStatus: block.status,
    phase,
    boundaryVertices: vertices.map((v) => ({
      id: v.id,
      sequence: v.sequence,
      latitude: parseFloat(String(v.latitude)),
      longitude: parseFloat(String(v.longitude)),
      recordedAt: v.recorded_at,
    })),
    buildings: buildings.map((b) => ({
      id: b.id,
      buildingNumber: b.building_number,
      censusHouseCount: b.census_house_count,
      buildingType: b.building_type,
      latitude: b.latitude != null ? parseFloat(String(b.latitude)) : null,
      longitude: b.longitude != null ? parseFloat(String(b.longitude)) : null,
      mapX: b.map_x,
      mapY: b.map_y,
      routeSequence: b.route_sequence,
    })),
    landmarks: landmarks.map((l) => ({
      id: l.id,
      name: l.name,
      landmarkType: l.landmark_type,
      mapX: l.map_x,
      mapY: l.map_y,
      latitude: l.latitude != null ? parseFloat(String(l.latitude)) : null,
      longitude: l.longitude != null ? parseFloat(String(l.longitude)) : null,
    })),
    breadcrumbs: breadcrumbs.map((b) => ({
      id: b.id,
      latitude: parseFloat(String(b.latitude)),
      longitude: parseFloat(String(b.longitude)),
      accuracy: b.accuracy != null ? parseFloat(String(b.accuracy)) : null,
      recordedAt: b.recorded_at,
    })),
    gapResolutions: resolutions.map((r) => ({
      gapFingerprint: r.gap_fingerprint,
      gapType: r.gap_type,
      gapReason: r.gap_reason,
      resolution: r.resolution,
      notes: r.notes,
      latitude: r.latitude != null ? parseFloat(String(r.latitude)) : null,
      longitude: r.longitude != null ? parseFloat(String(r.longitude)) : null,
      resolvedAt: r.resolved_at,
    })),
    officialBoundary: officialBoundary
      ? {
          id: officialBoundary.id,
          hlbCode: officialBoundary.hlbCode,
          name: officialBoundary.name,
          boundaryPolygon: officialBoundary.boundaryPolygon,
          areaSqMeters: officialBoundary.areaSqMeters,
          northDescription: officialBoundary.northDescription,
          southDescription: officialBoundary.southDescription,
          eastDescription: officialBoundary.eastDescription,
          westDescription: officialBoundary.westDescription,
          source: officialBoundary.source,
          startPoint: officialBoundary.startPoint,
          importedAt: officialBoundary.importedAt,
        }
      : null,
    boundaryAudit: audit,
    layoutGeoref: layoutGeoref
      ? {
          id: layoutGeoref.id,
          status: layoutGeoref.status,
          alignmentMode: layoutGeoref.alignmentMode,
          imageBounds: layoutGeoref.imageBounds,
          gpsBoundary: layoutGeoref.gpsBoundary,
          potentialStructures: layoutGeoref.potentialStructures,
          missionIntelligence: layoutGeoref.missionIntelligence,
          alignmentQualityPercent: layoutGeoref.alignmentQualityPercent,
          controlPoints: layoutGeoref.controlPoints,
          sketchBoundary: layoutGeoref.sketchBoundary,
          affineMatrix: layoutGeoref.affineMatrix,
          alignmentScore: layoutGeoref.alignmentScore,
          rmsErrorMeters: layoutGeoref.rmsErrorMeters,
          landmarks: layoutGeoref.landmarks,
          roads: layoutGeoref.roads,
          waterBodies: layoutGeoref.waterBodies,
          createdAt: layoutGeoref.createdAt,
          finalizedAt: layoutGeoref.finalizedAt,
        }
      : null,
    syncedAt: new Date().toISOString(),
  };
}
