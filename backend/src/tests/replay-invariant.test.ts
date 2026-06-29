import { describe, expect, it, beforeEach } from 'vitest';
import type { EvidenceEnvelope } from '../domains/evidence/types.js';
import { verifyEvidenceChain, computeRecordHash, canonicalizeForHash } from '../domains/evidence/hash.js';
import { replayPipeline } from '../domains/pipeline/replay-pipeline.js';
import { buildWorldProjection } from '../domains/projections/world-projection.js';
import { buildReplayProjection } from '../domains/projections/replay-projection.js';
import { computePredictionAccuracy, clearFlowMetrics } from '../domains/metrics/flow-metrics.js';

function chainEvents(events: Omit<EvidenceEnvelope, 'hash' | 'previousHash'>[]): EvidenceEnvelope[] {
  let previousHash: string | null = null;
  return events.map((e) => {
    const body = canonicalizeForHash({
      missionId: e.missionId,
      aggregateId: e.aggregateId,
      aggregateType: e.aggregateType,
      evidenceType: e.evidenceType,
      schemaVersion: e.schemaVersion,
      payload: e.payload,
      occurredAt: e.occurredAt,
      actor: e.actor,
      device: e.device,
    });
    const hash = computeRecordHash(previousHash, body);
    const envelope: EvidenceEnvelope = { ...e, hash, previousHash };
    previousHash = hash;
    return envelope;
  });
}

const missionId = 'mission-1';

const sampleMissionEvents = () =>
  chainEvents([
    {
      id: 'e1',
      missionId,
      aggregateId: missionId,
      aggregateType: 'mission',
      evidenceType: 'mission_imported',
      schemaVersion: '1',
      payload: {
        regions: [
          { id: 'region-18', confidence: 0.9 },
          { id: 'region-19', confidence: 0.8 },
        ],
      },
      occurredAt: '2026-06-01T09:00:00.000Z',
      receivedAt: '2026-06-01T09:00:01.000Z',
      actor: { userId: 'user-1' },
      device: null,
      sequenceNum: 1,
    },
    {
      id: 'e2',
      missionId,
      aggregateId: 'boundary',
      aggregateType: 'boundary',
      evidenceType: 'boundary_accepted',
      schemaVersion: '1',
      payload: {},
      occurredAt: '2026-06-01T09:05:00.000Z',
      receivedAt: '2026-06-01T09:05:01.000Z',
      actor: { userId: 'user-1' },
      device: null,
      sequenceNum: 2,
    },
    {
      id: 'e3',
      missionId,
      aggregateId: 'region-18',
      aggregateType: 'observation_region',
      evidenceType: 'region_confirmed',
      schemaVersion: '1',
      payload: { regionId: 'region-18', lat: 12.91, lng: 77.61, photoHash: 'abc' },
      occurredAt: '2026-06-01T10:00:00.000Z',
      receivedAt: '2026-06-01T10:00:01.000Z',
      actor: { userId: 'user-1' },
      device: null,
      sequenceNum: 3,
    },
  ]);

describe('ReplayInvariantTest', () => {
  beforeEach(() => clearFlowMetrics());

  it('KnowledgeGraphA equals KnowledgeGraphB after full evidence replay', () => {
    const events = sampleMissionEvents();
    expect(verifyEvidenceChain(events)).toBe(true);

    const graphA = replayPipeline(events).graph;
    const graphB = replayPipeline(events).graph;

    expect(graphB).toEqual(graphA);
    expect(graphA.aggregates.buildings['building-region-18']?.state).toBe('VALIDATED');
    expect(graphA.aggregates.buildings['building-region-18']?.aggregateVersion).toBe(1);
    expect(graphA.aggregates.boundary?.state).toBe('VALIDATED');
  });

  it('WorldProjection rebuild equals cached projection from same graph', () => {
    const events = sampleMissionEvents();
    const { graph } = replayPipeline(events);
    const worldA = buildWorldProjection(graph);
    const worldB = buildWorldProjection(graph);

    expect(worldB).toEqual(worldA);
    expect(worldA.stats.validatedBuildingCount).toBe(1);
    expect(worldA.missionVersion).toBeGreaterThan(0);
  });

  it('ReplayProjection proves deterministic evidence → domain events path', () => {
    const events = sampleMissionEvents();
    const { graph, domainEvents } = replayPipeline(events);
    const replayA = buildReplayProjection(
      events,
      domainEvents,
      computePredictionAccuracy(missionId, graph)
    );
    const replayB = buildReplayProjection(
      events,
      domainEvents,
      computePredictionAccuracy(missionId, graph)
    );

    expect(replayB).toEqual(replayA);
    expect(replayA.integrity.verified).toBe(true);
    expect(replayA.domainEvents.some((e) => e.type === 'BuildingCreated')).toBe(true);
    expect(replayA.metrics.predictionAccuracy.validated).toBe(1);
  });

  it('Domain events emitted for RegionObserved path', () => {
    const events = chainEvents([
      {
        id: 'e1',
        missionId,
        aggregateId: 'region-18',
        aggregateType: 'observation_region',
        evidenceType: 'gps_visit',
        schemaVersion: '1',
        payload: { regionId: 'region-18', lat: 12.9, lng: 77.6 },
        occurredAt: '2026-06-01T10:00:00.000Z',
        receivedAt: '2026-06-01T10:00:01.000Z',
        actor: { userId: 'user-1' },
        device: null,
        sequenceNum: 1,
      },
    ]);

    const { domainEvents } = replayPipeline(events);
    expect(domainEvents.some((e) => e.type === 'RegionObserved')).toBe(true);
  });
});

describe('Evidence hash chain', () => {
  it('detects tampered evidence', () => {
    const events = chainEvents([
      {
        id: 'e1',
        missionId,
        aggregateId: 'region-18',
        aggregateType: 'observation_region',
        evidenceType: 'gps_visit',
        schemaVersion: '1',
        payload: { regionId: 'region-18', lat: 1, lng: 2 },
        occurredAt: '2026-01-01T00:00:00.000Z',
        receivedAt: '2026-01-01T00:00:01.000Z',
        actor: { userId: 'user-1' },
        device: null,
        sequenceNum: 1,
      },
    ]);
    events[0].hash = 'tampered';
    expect(verifyEvidenceChain(events)).toBe(false);
  });
});
