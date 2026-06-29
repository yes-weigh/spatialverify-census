import {
  FACT_ENGINE_VERSION,
  REASONING_ENGINE_VERSION,
  type EvidenceEnvelope,
} from '../evidence/types.js';
import { initMissionAggregate } from '../knowledge-graph/graph-builder.js';

export type KnowledgeState =
  | 'UNKNOWN'
  | 'PREDICTED'
  | 'OBSERVED'
  | 'VALIDATED'
  | 'REJECTED'
  | 'IGNORED';

/** Aggregate roots — each owns a slice of the canonical graph. */
export interface MissionAggregate {
  aggregateType: 'mission';
  aggregateVersion: number;
  state: KnowledgeState;
}

export interface BoundaryAggregate {
  aggregateType: 'boundary';
  aggregateId: string;
  aggregateVersion: number;
  state: KnowledgeState;
}

export interface ObservationRegionAggregate {
  aggregateType: 'observation_region';
  aggregateId: string;
  aggregateVersion: number;
  state: KnowledgeState;
  confidence: number;
  supersededByBuildingId?: string;
}

export interface BuildingAggregate {
  aggregateType: 'building';
  aggregateId: string;
  aggregateVersion: number;
  state: KnowledgeState;
  sourceRegionId?: string;
  lat?: number;
  lng?: number;
}

export interface KnowledgeGraph {
  missionId: string;
  meta: {
    factEngineVersion: string;
    reasoningEngineVersion: string;
    lastEvidenceSequence: number;
    builtAt: string;
  };
  aggregates: {
    mission: MissionAggregate;
    boundary: BoundaryAggregate | null;
    observationRegions: Record<string, ObservationRegionAggregate>;
    buildings: Record<string, BuildingAggregate>;
  };
}

export function emptyKnowledgeGraph(missionId: string): KnowledgeGraph {
  return {
    missionId,
    meta: {
      factEngineVersion: FACT_ENGINE_VERSION,
      reasoningEngineVersion: REASONING_ENGINE_VERSION,
      lastEvidenceSequence: 0,
      builtAt: new Date().toISOString(),
    },
    aggregates: {
      mission: initMissionAggregate(),
      boundary: null,
      observationRegions: {},
      buildings: {},
    },
  };
}

import { buildKnowledgeGraphFromEvidence as buildFromReplay } from '../pipeline/replay-pipeline.js';

export function buildKnowledgeGraphFromEvidence(events: EvidenceEnvelope[]): KnowledgeGraph {
  return buildFromReplay(events);
}
