import type { EvidenceEnvelope } from '../evidence/types.js';
import type { DomainEvent } from '../domain-events/types.js';
import { verifyEvidenceChain } from '../evidence/hash.js';
import { REPLAY_PROJECTION_VERSION } from '../evidence/types.js';

/** ReplayProjection — reads Evidence + Domain Events only (never other projections). */
export interface ReplayProjection {
  missionId: string;
  builderVersion: string;
  builtAt: string;
  integrity: {
    verified: boolean;
    evidenceCount: number;
    violationCount: number;
  };
  timeline: Array<{
    sequenceNum: number;
    kind: 'evidence' | 'domain_event';
    at: string;
    type: string;
    aggregateId: string;
    summary: string;
  }>;
  domainEvents: DomainEvent[];
  metrics: {
    predictionAccuracy: {
      expected: number;
      validated: number;
      rejected: number;
      ignored: number;
      pending: number;
    };
  };
}

export function buildReplayProjection(
  evidence: EvidenceEnvelope[],
  domainEvents: DomainEvent[],
  predictionAccuracy: ReplayProjection['metrics']['predictionAccuracy']
): ReplayProjection {
  const chainValid = evidence.length === 0 || verifyEvidenceChain(evidence);
  const timeline: ReplayProjection['timeline'] = [];

  for (const e of evidence) {
    timeline.push({
      sequenceNum: e.sequenceNum,
      kind: 'evidence',
      at: e.occurredAt,
      type: `${e.evidenceType}@${e.schemaVersion}`,
      aggregateId: e.aggregateId,
      summary: `Evidence ${e.evidenceType} on ${e.aggregateType}:${e.aggregateId}`,
    });
  }

  for (const de of domainEvents) {
    timeline.push({
      sequenceNum: de.evidenceSequenceNum,
      kind: 'domain_event',
      at: de.occurredAt,
      type: de.type,
      aggregateId: de.aggregateId,
      summary: `Domain ${de.type} on ${de.aggregateType}:${de.aggregateId}`,
    });
  }

  timeline.sort((a, b) => a.sequenceNum - b.sequenceNum || a.at.localeCompare(b.at));

  const builtAt = evidence.length > 0 ? evidence[evidence.length - 1].occurredAt : new Date().toISOString();

  return {
    missionId: evidence[0]?.missionId ?? '',
    builderVersion: REPLAY_PROJECTION_VERSION,
    builtAt,
    integrity: {
      verified: chainValid,
      evidenceCount: evidence.length,
      violationCount: chainValid ? 0 : 1,
    },
    timeline,
    domainEvents,
    metrics: { predictionAccuracy },
  };
}
