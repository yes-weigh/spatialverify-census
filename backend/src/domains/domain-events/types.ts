import type { AggregateType } from '../evidence/types.js';

/** Consequences of reasoning — not evidence, not facts. Projections may subscribe to these. */
export type DomainEventType =
  | 'RegionPredicted'
  | 'RegionObserved'
  | 'RegionValidated'
  | 'RegionRejected'
  | 'RegionIgnored'
  | 'BuildingCreated'
  | 'BoundaryValidated'
  | 'MissionProgressChanged';

export interface DomainEvent {
  type: DomainEventType;
  missionId: string;
  aggregateId: string;
  aggregateType: AggregateType;
  occurredAt: string;
  derivedFromEvidenceId: string;
  evidenceSequenceNum: number;
  payload: Record<string, unknown>;
}
