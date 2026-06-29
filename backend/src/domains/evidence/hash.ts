import { createHash } from 'node:crypto';
import type { EvidenceEnvelope } from './types.js';

/** Canonical JSON for hashing — stable key order, excludes hash fields. */
export function canonicalizeForHash(input: {
  missionId: string;
  aggregateId: string;
  aggregateType: string;
  evidenceType: string;
  schemaVersion: string;
  payload: Record<string, unknown>;
  occurredAt: string;
  actor: unknown;
  device: unknown;
}): string {
  return JSON.stringify({
    aggregateId: input.aggregateId,
    aggregateType: input.aggregateType,
    actor: input.actor,
    device: input.device,
    evidenceType: input.evidenceType,
    missionId: input.missionId,
    occurredAt: input.occurredAt,
    payload: input.payload,
    schemaVersion: input.schemaVersion,
  });
}

export function computeRecordHash(previousHash: string | null, canonicalBody: string): string {
  const material = previousHash ? `${previousHash}:${canonicalBody}` : canonicalBody;
  return createHash('sha256').update(material, 'utf8').digest('hex');
}

export function hashEnvelopeBody(
  previousHash: string | null,
  input: Omit<EvidenceEnvelope, 'id' | 'hash' | 'previousHash' | 'sequenceNum' | 'receivedAt'>
): string {
  return computeRecordHash(previousHash, canonicalizeForHash(input));
}

/** Verify hash chain for a mission's evidence (audit). */
export function verifyEvidenceChain(events: EvidenceEnvelope[]): boolean {
  let expectedPrevious: string | null = null;
  for (const event of events) {
    if (event.previousHash !== expectedPrevious) return false;
    const body = canonicalizeForHash({
      missionId: event.missionId,
      aggregateId: event.aggregateId,
      aggregateType: event.aggregateType,
      evidenceType: event.evidenceType,
      schemaVersion: event.schemaVersion,
      payload: event.payload,
      occurredAt: event.occurredAt,
      actor: event.actor,
      device: event.device,
    });
    const expected = computeRecordHash(event.previousHash, body);
    if (expected !== event.hash) return false;
    expectedPrevious = event.hash;
  }
  return true;
}
