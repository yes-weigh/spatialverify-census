import type { Fact } from '../facts/fact-engine.js';
import type { DomainEvent } from '../domain-events/types.js';
import type { EvidenceEnvelope } from '../evidence/types.js';

export interface FlowMetricRecord {
  missionId: string;
  metricType: string;
  aggregateId?: string;
  startedAt?: string;
  completedAt: string;
  durationMs?: number;
  payload: Record<string, unknown>;
}

const metricsByMission = new Map<string, FlowMetricRecord[]>();

/** In-memory flow metrics — persist to DB when analytics pipeline exists. */
export function recordFlowMetrics(
  missionId: string,
  fact: Fact,
  domainEvents: DomainEvent[],
  allEvidence: EvidenceEnvelope[]
): void {
  const list = metricsByMission.get(missionId) ?? [];
  const now = fact.occurredAt;

  if (domainEvents.some((e) => e.type === 'RegionObserved')) {
    const predicted = allEvidence.find(
      (e) =>
        e.evidenceType === 'mission_imported' &&
        (e.payload.regions as Array<{ id: string }>)?.some((r) => r.id === fact.aggregateId)
    );
    if (predicted) {
      const durationMs =
        new Date(now).getTime() - new Date(predicted.occurredAt).getTime();
      list.push({
        missionId,
        metricType: 'region_predicted_to_observed',
        aggregateId: fact.aggregateId,
        startedAt: predicted.occurredAt,
        completedAt: now,
        durationMs,
        payload: { regionId: fact.aggregateId },
      });
    }
  }

  if (domainEvents.some((e) => e.type === 'BuildingCreated')) {
    const observed = allEvidence.find(
      (e) =>
        (e.evidenceType === 'gps_visit' || e.evidenceType === 'entered_region') &&
        (e.payload.regionId === fact.aggregateId || e.aggregateId === fact.aggregateId)
    );
    const confirmed = allEvidence.find(
      (e) => e.evidenceType === 'region_confirmed' && e.payload.regionId === fact.aggregateId
    );
    if (observed && confirmed) {
      list.push({
        missionId,
        metricType: 'region_observed_to_confirmed',
        aggregateId: fact.aggregateId,
        startedAt: observed.occurredAt,
        completedAt: confirmed.occurredAt,
        durationMs:
          new Date(confirmed.occurredAt).getTime() - new Date(observed.occurredAt).getTime(),
        payload: { regionId: fact.aggregateId },
      });
    }
  }

  if (domainEvents.some((e) => e.type === 'MissionProgressChanged')) {
    const progress = domainEvents.find((e) => e.type === 'MissionProgressChanged');
    if (progress) {
      list.push({
        missionId,
        metricType: 'mission_progress_snapshot',
        completedAt: now,
        payload: progress.payload,
      });
    }
  }

  metricsByMission.set(missionId, list);
}

export function getFlowMetrics(missionId: string): FlowMetricRecord[] {
  return metricsByMission.get(missionId) ?? [];
}

export function clearFlowMetrics(missionId?: string): void {
  if (missionId) metricsByMission.delete(missionId);
  else metricsByMission.clear();
}

export function computePredictionAccuracy(missionId: string, graph: {
  aggregates: {
    observationRegions: Record<string, { state: string }>;
    buildings: Record<string, { state: string }>;
  };
}): {
  expected: number;
  validated: number;
  rejected: number;
  ignored: number;
  pending: number;
} {
  const regions = Object.values(graph.aggregates.observationRegions);
  return {
    expected: regions.length,
    validated: regions.filter((r) => r.state === 'VALIDATED').length,
    rejected: regions.filter((r) => r.state === 'REJECTED').length,
    ignored: regions.filter((r) => r.state === 'IGNORED').length,
    pending: regions.filter((r) => ['PREDICTED', 'OBSERVED'].includes(r.state)).length,
  };
}
