/** Evidence domain — canonical envelope for all producers (GPS, camera, CV, documents, …). */

export type AggregateType =
  | 'mission'
  | 'boundary'
  | 'observation_region'
  | 'building'
  | 'gap'
  | 'coverage_cell'
  | 'expectation';

/** Schema-versioned evidence types. Replay uses evidenceType + schemaVersion. */
export type EvidenceTypeId =
  | 'mission_imported'
  | 'boundary_accepted'
  | 'boundary_adjusted'
  | 'walk_started'
  | 'breadcrumb_recorded'
  | 'entered_region'
  | 'camera_opened'
  | 'photo_captured'
  | 'region_confirmed'
  | 'region_rejected'
  | 'region_ignored'
  | 'gap_detected'
  | 'gap_resolved'
  | 'building_classified'
  | 'listing_completed'
  | 'mission_completed'
  | 'mission_audited'
  | 'gps_visit';

export interface EvidenceActor {
  userId: string;
  role?: string;
}

export interface EvidenceDevice {
  id?: string;
  platform?: string;
}

/** Canonical envelope — every producer must emit this shape. */
export interface EvidenceEnvelope {
  id: string;
  missionId: string;
  aggregateId: string;
  aggregateType: AggregateType;
  evidenceType: EvidenceTypeId;
  schemaVersion: string;
  payload: Record<string, unknown>;
  occurredAt: string;
  receivedAt: string;
  actor: EvidenceActor | null;
  device: EvidenceDevice | null;
  hash: string;
  previousHash: string | null;
  sequenceNum: number;
}

export interface AppendEvidenceInput {
  missionId: string;
  aggregateId: string;
  aggregateType: AggregateType;
  evidenceType: EvidenceTypeId;
  schemaVersion: string;
  payload: Record<string, unknown>;
  occurredAt: string;
  actor: EvidenceActor | null;
  device: EvidenceDevice | null;
}

export const FACT_ENGINE_VERSION = '1.0.0';
export const REASONING_ENGINE_VERSION = '1.0.0';
export const WORLD_PROJECTION_VERSION = '1.0.0';
export const REPLAY_PROJECTION_VERSION = '1.0.0';
