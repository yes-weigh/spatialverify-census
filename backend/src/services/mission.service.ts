import { missionRepository } from '../repositories/mission.repository.js';
import { storageService } from './storage.service.js';
import type {
  CoverageAnalysis,
  DayReview,
  MissionBuilding,
  MissionDashboard,
  SaveMissionPlanInput,
  SupervisorMissionSummary,
} from '../types/mission.js';
import { findSmartNextBuilding, estimateRemainingMinutes } from '../utils/mission-navigation.js';
import { haversineMeters } from '../utils/geo.js';
import { buildDiscoveryStatus, getDraftMapPayload, suggestNumberAtGps } from './hlb-discovery.service.js';
import { buildCoverageGapsResponse, resolveCoverageGap } from './coverage-gap.service.js';
import { computeBounds, projectToMapCoords } from '../utils/serpentine-numbering.js';

function mapBuilding(row: Record<string, unknown>): MissionBuilding {
  return {
    id: row.id as string,
    eb_id: row.eb_id as string,
    building_number: row.building_number as number,
    census_house_count: row.census_house_count as number,
    building_type: row.building_type as MissionBuilding['building_type'],
    map_x: parseFloat(String(row.map_x)),
    map_y: parseFloat(String(row.map_y)),
    latitude: row.latitude != null ? parseFloat(String(row.latitude)) : null,
    longitude: row.longitude != null ? parseFloat(String(row.longitude)) : null,
    route_sequence: row.route_sequence as number | null,
    status: row.status as MissionBuilding['status'],
    notes: row.notes as string | null,
    asset_id: row.asset_id as string | null,
    visited_at: row.visited_at as string | null,
    completed_at: row.completed_at as string | null,
    completed_by: row.completed_by as string | null,
  };
}

export class MissionService {
  async getLayoutImageUrl(layoutKey: string | null): Promise<string | null> {
    if (!layoutKey) return null;
    try {
      return await storageService.getPresignedDownloadUrl(layoutKey, 7200);
    } catch {
      return null;
    }
  }

  async getFullPlan(ebId: string) {
    const block = await missionRepository.findBlockById(ebId);
    if (!block) return null;

    const [buildings, landmarks, layoutImageUrl] = await Promise.all([
      missionRepository.getBuildings(ebId),
      missionRepository.getLandmarks(ebId),
      this.getLayoutImageUrl(block.layout_image_key as string | null),
    ]);

    return {
      block,
      buildings: buildings.map(mapBuilding),
      landmarks,
      layoutImageUrl,
    };
  }

  async getDashboard(ebId: string, lat?: number, lng?: number): Promise<MissionDashboard | null> {
    const block = await missionRepository.findBlockById(ebId);
    if (!block) return null;

    const [stats, buildings, layoutImageUrl] = await Promise.all([
      missionRepository.getBuildingStats(ebId),
      missionRepository.getBuildings(ebId),
      this.getLayoutImageUrl(block.layout_image_key as string | null),
    ]);

    const mapped = buildings.map(mapBuilding);
    const { building: nextBuilding, strategy } = findSmartNextBuilding(
      mapped,
      block.route_building_ids as string[],
      lat,
      lng
    );

    const total = stats.total as number;
    const completed = stats.completed as number;
    const remaining = total - completed;

    return {
      ebId,
      ebCode: block.eb_code as string,
      ebName: block.name as string | null,
      status: block.status as MissionDashboard['status'],
      totalBuildings: total,
      completedBuildings: completed,
      visitedBuildings: stats.visited as number,
      revisitRequired: stats.revisit as number,
      remainingBuildings: remaining,
      progressPercent: total > 0 ? Math.round((completed / total) * 1000) / 10 : 0,
      nextBuilding,
      nextBuildingStrategy: strategy,
      layoutImageUrl,
    };
  }

  findNextBuilding(buildings: MissionBuilding[], routeIds: string[]): MissionBuilding | null {
    return findSmartNextBuilding(buildings, routeIds).building;
  }

  async getDayReview(ebId: string, lat?: number, lng?: number): Promise<DayReview | null> {
    const block = await missionRepository.findBlockById(ebId);
    if (!block) return null;

    const [stats, pendingRows, avgTravel, avgSurvey] = await Promise.all([
      missionRepository.getBuildingStats(ebId),
      missionRepository.getPendingBuildings(ebId),
      missionRepository.getAverageTravelSeconds(ebId),
      missionRepository.getAverageSurveySeconds(ebId),
    ]);

    const pending = pendingRows.map(mapBuilding);
    const total = stats.total as number;
    const completed = stats.completed as number;
    const remaining = pending.length;

    const avgTravelMinutes = avgTravel != null ? Math.max(1, Math.round(avgTravel / 60)) : 3;
    const avgSurveyMinutes = avgSurvey != null ? Math.max(2, Math.round(avgSurvey / 60)) : 4;

    const estimatedRemainingMinutes = estimateRemainingMinutes(
      pending,
      lat,
      lng,
      avgTravelMinutes,
      avgSurveyMinutes
    );

    return {
      ebId,
      ebCode: block.eb_code as string,
      progressPercent: total > 0 ? Math.round((completed / total) * 1000) / 10 : 0,
      completedBuildings: completed,
      remainingBuildings: remaining,
      remainingBuildingNumbers: pending.map((b) => b.building_number).sort((a, b) => a - b),
      estimatedRemainingMinutes,
      avgMinutesPerBuilding: avgTravelMinutes + avgSurveyMinutes,
    };
  }

  async recordTravelOnComplete(
    ebId: string,
    toBuildingId: string,
    userId: string,
    toLat?: number,
    toLng?: number
  ) {
    const last = await missionRepository.getLastCompletedBuilding(ebId, toBuildingId);
    if (!last?.completed_at) return;

    const travelSeconds = Math.floor(
      (Date.now() - new Date(last.completed_at as string).getTime()) / 1000
    );
    // Skip long gaps (breaks, end of previous day)
    if (travelSeconds <= 0 || travelSeconds > 7200) return;

    let distanceMeters: number | null = null;
    if (
      last.latitude != null &&
      last.longitude != null &&
      toLat != null &&
      toLng != null
    ) {
      distanceMeters = haversineMeters(
        parseFloat(String(last.latitude)),
        parseFloat(String(last.longitude)),
        toLat,
        toLng
      );
    }

    await missionRepository.recordTravelSegment({
      ebId,
      fromBuildingId: last.id as string,
      toBuildingId,
      userId,
      travelSeconds,
      distanceMeters,
    });
  }

  async getRouteList(ebId: string): Promise<MissionBuilding[]> {
    const block = await missionRepository.findBlockById(ebId);
    if (!block) return [];

    const buildings = (await missionRepository.getBuildings(ebId)).map(mapBuilding);
    const routeIds = block.route_building_ids as string[];

    if (!routeIds?.length) {
      return buildings.sort((a, b) => a.building_number - b.building_number);
    }

    const byId = new Map(buildings.map((b) => [b.id, b]));
    const ordered: MissionBuilding[] = [];
    for (const id of routeIds) {
      const b = byId.get(id);
      if (b) ordered.push(b);
    }
    for (const b of buildings) {
      if (!routeIds.includes(b.id)) ordered.push(b);
    }
    return ordered;
  }

  async analyzeCoverage(ebId: string): Promise<CoverageAnalysis | null> {
    const block = await missionRepository.findBlockById(ebId);
    if (!block) return null;

    const [buildings, breadcrumbs, stats] = await Promise.all([
      missionRepository.getBuildings(ebId),
      missionRepository.getBreadcrumbs(ebId),
      missionRepository.getBuildingStats(ebId),
    ]);

    const mapped = buildings.map(mapBuilding);
    const notVisited = mapped.filter((b) => b.status === 'not_visited');
    const revisit = mapped.filter((b) => b.status === 'revisit_required');

    const potentiallyMissedAreas: CoverageAnalysis['potentiallyMissedAreas'] = [];

    if (notVisited.length > 0) {
      potentiallyMissedAreas.push({
        reason: 'unvisited_buildings',
        buildingIds: notVisited.map((b) => b.id),
        description: `${notVisited.length} building(s) not yet visited`,
      });
    }

    if (revisit.length > 0) {
      potentiallyMissedAreas.push({
        reason: 'revisit_required',
        buildingIds: revisit.map((b) => b.id),
        description: `${revisit.length} building(s) flagged for revisit`,
      });
    }

    // GPS vs boundary check when real-world boundary exists
    const { query } = await import('../db/pool.js');
    const { rows: hasBoundary } = await query(
      `SELECT boundary IS NOT NULL AS has_boundary FROM enumeration_blocks WHERE id = $1`,
      [ebId]
    );

    if (hasBoundary[0]?.has_boundary) {
      const { rows: outside } = await query(
        `SELECT COUNT(*)::int AS cnt FROM mission_gps_breadcrumbs b
         WHERE b.eb_id = $1
           AND NOT ST_Within(b.location, (SELECT boundary FROM enumeration_blocks WHERE id = $1))`,
        [ebId]
      );
      if ((outside[0]?.cnt as number) > 0) {
        potentiallyMissedAreas.push({
          reason: 'gps_outside_boundary',
          description: `${outside[0].cnt} GPS points outside EB boundary — verify assigned area`,
        });
      }
    }

    if (breadcrumbs.length === 0 && mapped.length > 0) {
      potentiallyMissedAreas.push({
        reason: 'no_gps_trail',
        description: 'No GPS breadcrumbs recorded — enable location tracking during survey',
      });
    }

    const total = stats.total as number;
    const completed = stats.completed as number;

    return {
      ebId,
      totalBuildings: total,
      notVisitedBuildings: notVisited,
      revisitBuildings: revisit,
      breadcrumbCount: breadcrumbs.length,
      potentiallyMissedAreas,
      coveragePercent: total > 0 ? Math.round((completed / total) * 1000) / 10 : 0,
    };
  }

  async getSupervisorSummary(projectId: string): Promise<SupervisorMissionSummary> {
    const rows = await missionRepository.supervisorSummary(projectId);

    return {
      projectId,
      blocks: rows.map((r: Record<string, unknown>) => {
        const total = r.total_buildings as number;
        const completed = r.completed_buildings as number;
        return {
          ebId: r.eb_id as string,
          ebCode: r.eb_code as string,
          name: r.name as string | null,
          status: r.status as SupervisorMissionSummary['blocks'][0]['status'],
          assignedEnumeratorId: r.assigned_enumerator_id as string | null,
          assignedEnumeratorName: r.enumerator_name as string | null,
          totalBuildings: total,
          completedBuildings: completed,
          progressPercent: total > 0 ? Math.round((completed / total) * 1000) / 10 : 0,
          missedCount: r.missed_count as number,
          revisitCount: r.revisit_count as number,
        };
      }),
    };
  }

  async savePlan(ebId: string, plan: SaveMissionPlanInput) {
    return missionRepository.replaceMissionPlan(ebId, plan);
  }

  async getDiscovery(ebId: string) {
    return buildDiscoveryStatus(ebId);
  }

  async getDraftMap(ebId: string) {
    return getDraftMapPayload(ebId);
  }

  async suggestSerpentineNumber(ebId: string, lat: number, lng: number) {
    const num = await suggestNumberAtGps(ebId, lat, lng);
    return { buildingNumber: num, label: `CN-${String(num).padStart(3, '0')}` };
  }

  async getCoverageGaps(ebId: string, lat?: number, lng?: number) {
    return buildCoverageGapsResponse(ebId, lat, lng);
  }

  async resolveCoverageGap(
    ebId: string,
    gapId: string,
    userId: string,
    data: {
      resolution: 'building_found' | 'no_building' | 'not_accessible' | 'investigated';
      notes?: string;
      gapType: string;
      gapReason: string;
      latitude?: number | null;
      longitude?: number | null;
      resolvedLatitude?: number | null;
      resolvedLongitude?: number | null;
    }
  ) {
    return resolveCoverageGap(ebId, gapId, { ...data, resolvedBy: userId });
  }

  async discoverBuilding(
    ebId: string,
    data: {
      latitude: number;
      longitude: number;
      buildingType: MissionBuilding['building_type'];
      censusHouseCount?: number;
      buildingNumber?: number;
    }
  ) {
    const buildingNumber =
      data.buildingNumber ??
      (await suggestNumberAtGps(ebId, data.latitude, data.longitude));

    const buildings = await missionRepository.getBuildings(ebId);
    const bounds = computeBounds([
      ...buildings.filter((b) => b.latitude != null).map((b) => ({
        latitude: parseFloat(String(b.latitude)),
        longitude: parseFloat(String(b.longitude)),
      })),
      { latitude: data.latitude, longitude: data.longitude },
    ]);
    const coords = projectToMapCoords(data.latitude, data.longitude, bounds);

    return missionRepository.addDiscoveredBuilding({
      ebId,
      buildingNumber,
      censusHouseCount: data.censusHouseCount ?? 1,
      buildingType: data.buildingType,
      latitude: data.latitude,
      longitude: data.longitude,
      mapX: Math.min(Math.max(coords.x, 0.05), 0.95),
      mapY: Math.min(Math.max(coords.y, 0.05), 0.95),
      routeSequence: buildingNumber,
    });
  }

  async addBoundaryVertex(ebId: string, lat: number, lng: number) {
    return missionRepository.addBoundaryVertex(ebId, lat, lng);
  }

  async discoverLandmark(
    ebId: string,
    data: {
      name: string;
      landmarkType: string;
      latitude: number;
      longitude: number;
    }
  ) {
    const landmarks = await missionRepository.getLandmarks(ebId);
    const mapX = 0.15 + (landmarks.length % 10) * 0.08;
    const mapY = 0.85;
    return missionRepository.addDiscoveredLandmark({
      ebId,
      name: data.name,
      landmarkType: data.landmarkType,
      latitude: data.latitude,
      longitude: data.longitude,
      mapX,
      mapY,
    });
  }

  /** Transition from HLB draft mapping to house listing phase. */
  async finalizeDraftMap(ebId: string) {
    const stats = await missionRepository.getBuildingStats(ebId);
    if ((stats.total as number) === 0) {
      throw new Error('Record at least one building before starting house listing');
    }
    return missionRepository.updateBlockMeta(ebId, { status: 'published' });
  }
}

export const missionService = new MissionService();
