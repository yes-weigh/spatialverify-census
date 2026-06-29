import type { EvidenceEnvelope } from './types.js';

export interface EvidenceRow {
  id: string;
  mission_id: string;
  aggregate_id: string;
  aggregate_type: string;
  evidence_type: string;
  schema_version: string;
  payload: Record<string, unknown>;
  occurred_at: Date;
  received_at: Date;
  actor_id: string | null;
  device_id: string | null;
  record_hash: string;
  previous_hash: string | null;
  sequence_num: string;
}

export function rowToEnvelope(row: EvidenceRow): EvidenceEnvelope {
  return {
    id: row.id,
    missionId: row.mission_id,
    aggregateId: row.aggregate_id,
    aggregateType: row.aggregate_type as EvidenceEnvelope['aggregateType'],
    evidenceType: row.evidence_type as EvidenceEnvelope['evidenceType'],
    schemaVersion: row.schema_version,
    payload: row.payload ?? {},
    occurredAt: row.occurred_at.toISOString(),
    receivedAt: row.received_at.toISOString(),
    actor: row.actor_id ? { userId: row.actor_id } : null,
    device: row.device_id ? { id: row.device_id } : null,
    hash: row.record_hash,
    previousHash: row.previous_hash,
    sequenceNum: Number(row.sequence_num),
  };
}
