import type { KnowledgeGraph } from '../reasoning/reasoning-engine.js';
import { WORLD_PROJECTION_VERSION } from '../evidence/types.js';

/** WorldProjection read model — reads ONLY from Knowledge Graph (never other projections). */
export interface WorldProjection {
  missionId: string;
  builderVersion: string;
  builtAt: string;
  boundary: { state: string } | null;
  observationRegions: Array<{
    id: string;
    state: string;
    confidence: number;
    aggregateVersion: number;
    supersededByBuildingId?: string;
  }>;
  buildings: Array<{
    id: string;
    state: string;
    aggregateVersion: number;
    sourceRegionId?: string;
    lat?: number;
    lng?: number;
  }>;
  missionVersion: number;
  stats: {
    regionCount: number;
    buildingCount: number;
    validatedBuildingCount: number;
  };
}

export function buildWorldProjection(graph: KnowledgeGraph): WorldProjection {
  const regions = Object.values(graph.aggregates.observationRegions);
  const buildings = Object.values(graph.aggregates.buildings);

  return {
    missionId: graph.missionId,
    builderVersion: WORLD_PROJECTION_VERSION,
    builtAt: graph.meta.builtAt,
    boundary: graph.aggregates.boundary
      ? { state: graph.aggregates.boundary.state }
      : null,
    missionVersion: graph.aggregates.mission.aggregateVersion,
    observationRegions: regions.map((r) => ({
      id: r.aggregateId,
      state: r.state,
      confidence: r.confidence,
      aggregateVersion: r.aggregateVersion,
      supersededByBuildingId: r.supersededByBuildingId,
    })),
    buildings: buildings.map((b) => ({
      id: b.aggregateId,
      state: b.state,
      aggregateVersion: b.aggregateVersion,
      sourceRegionId: b.sourceRegionId,
      lat: b.lat,
      lng: b.lng,
    })),
    stats: {
      regionCount: regions.length,
      buildingCount: buildings.length,
      validatedBuildingCount: buildings.filter((b) => b.state === 'VALIDATED').length,
    },
  };
}
