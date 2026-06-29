import { query } from '../../db/pool.js';
import { hashEnvelopeBody } from './hash.js';
import { rowToEnvelope, type EvidenceRow } from './serializer.js';
import type { AppendEvidenceInput, EvidenceEnvelope } from './types.js';

export class EvidenceRepository {
  async getLastEvent(missionId: string): Promise<EvidenceEnvelope | null> {
    const { rows } = await query<EvidenceRow>(
      `SELECT * FROM evidence_events
       WHERE mission_id = $1
       ORDER BY sequence_num DESC
       LIMIT 1`,
      [missionId]
    );
    return rows[0] ? rowToEnvelope(rows[0]) : null;
  }

  async listByMission(missionId: string): Promise<EvidenceEnvelope[]> {
    const { rows } = await query<EvidenceRow>(
      `SELECT * FROM evidence_events
       WHERE mission_id = $1
       ORDER BY sequence_num ASC`,
      [missionId]
    );
    return rows.map(rowToEnvelope);
  }

  async append(input: AppendEvidenceInput): Promise<EvidenceEnvelope> {
    const last = await this.getLastEvent(input.missionId);
    const previousHash = last?.hash ?? null;
    const nextSequence = (last?.sequenceNum ?? 0) + 1;

    const hash = hashEnvelopeBody(previousHash, {
      missionId: input.missionId,
      aggregateId: input.aggregateId,
      aggregateType: input.aggregateType,
      evidenceType: input.evidenceType,
      schemaVersion: input.schemaVersion,
      payload: input.payload,
      occurredAt: input.occurredAt,
      actor: input.actor,
      device: input.device,
    });

    const { rows } = await query<EvidenceRow>(
      `INSERT INTO evidence_events (
        mission_id, aggregate_id, aggregate_type, evidence_type, schema_version,
        payload, occurred_at, actor_id, device_id, record_hash, previous_hash, sequence_num
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
      RETURNING *`,
      [
        input.missionId,
        input.aggregateId,
        input.aggregateType,
        input.evidenceType,
        input.schemaVersion,
        JSON.stringify(input.payload),
        input.occurredAt,
        input.actor?.userId ?? null,
        input.device?.id ?? null,
        hash,
        previousHash,
        nextSequence,
      ]
    );

    return rowToEnvelope(rows[0]);
  }
}

export const evidenceRepository = new EvidenceRepository();
