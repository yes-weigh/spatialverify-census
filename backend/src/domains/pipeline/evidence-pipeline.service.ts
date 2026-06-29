import { deriveFactsFromEvidence } from '../facts/fact-engine.js';
import { evidenceReplay } from '../evidence/evidence-replay.js';
import { evidenceRepository } from '../evidence/evidence.repository.js';
import { validateEvidencePayload } from '../evidence/validator.js';
import type { AppendEvidenceInput, EvidenceEnvelope } from '../evidence/types.js';
import { FACT_ENGINE_VERSION, REASONING_ENGINE_VERSION } from '../evidence/types.js';
import { knowledgeGraphRepository } from '../knowledge-graph/knowledge-graph.repository.js';
import { emptyKnowledgeGraph, type KnowledgeGraph } from '../reasoning/reasoning-engine.js';
import { replayPipeline } from './replay-pipeline.js';
import { buildWorldProjection } from '../projections/world-projection.js';
import { worldProjectionRepository } from '../projections/world-projection.repository.js';
import { buildReplayProjection } from '../projections/replay-projection.js';
import { replayProjectionRepository } from '../projections/replay-projection.repository.js';
import {
  computePredictionAccuracy,
  getFlowMetrics,
} from '../metrics/flow-metrics.js';
import { verifyEvidenceChain } from '../evidence/hash.js';

export class EvidencePipelineService {
  private runProjections(missionId: string, events: EvidenceEnvelope[]) {
    const { graph, domainEvents } = replayPipeline(events);
    const world = buildWorldProjection(graph);
    const replay = buildReplayProjection(
      events,
      domainEvents,
      computePredictionAccuracy(missionId, graph)
    );
    return { graph, domainEvents, world, replay };
  }

  /** Append evidence → replay → persist graph → rebuild World + Replay projections. */
  async appendAndProject(input: AppendEvidenceInput): Promise<{
    evidence: EvidenceEnvelope;
    graph: KnowledgeGraph;
    world: ReturnType<typeof buildWorldProjection>;
    replay: ReturnType<typeof buildReplayProjection>;
  }> {
    validateEvidencePayload(input.evidenceType, input.schemaVersion, input.payload);

    const evidence = await evidenceRepository.append(input);
    const events = await evidenceReplay.loadVerified(input.missionId);
    const { graph, world, replay } = this.runProjections(input.missionId, events);

    await knowledgeGraphRepository.save(graph, FACT_ENGINE_VERSION, REASONING_ENGINE_VERSION);
    await worldProjectionRepository.save(input.missionId, world, world.builderVersion);
    await replayProjectionRepository.save(input.missionId, replay, replay.builderVersion);

    return { evidence, graph, world, replay };
  }

  async getWorld(missionId: string) {
    const cached = await worldProjectionRepository.get(missionId);
    if (cached) return cached;

    const events = await evidenceReplay.loadVerified(missionId);
    if (events.length === 0) {
      return buildWorldProjection(emptyKnowledgeGraph(missionId));
    }

    const { graph } = replayPipeline(events);
    const world = buildWorldProjection(graph);
    await worldProjectionRepository.save(missionId, world, world.builderVersion);
    return world;
  }

  async getReplay(missionId: string) {
    const cached = await replayProjectionRepository.get(missionId);
    if (cached) return cached;

    const events = await evidenceReplay.loadVerified(missionId);
    const { graph, domainEvents } = replayPipeline(events);
    const replay = buildReplayProjection(
      events,
      domainEvents,
      computePredictionAccuracy(missionId, graph)
    );
    await replayProjectionRepository.save(missionId, replay, replay.builderVersion);
    return replay;
  }

  async getEvidenceIntegrity(missionId: string) {
    const events = await evidenceReplay.loadVerified(missionId);
    const verified = events.length === 0 || verifyEvidenceChain(events);
    return {
      missionId,
      verified,
      evidenceCount: events.length,
      violationCount: verified ? 0 : 1,
      message: verified
        ? `${events.length} evidence records — 0 integrity violations`
        : 'Evidence chain integrity check failed',
    };
  }

  async getFlowMetrics(missionId: string) {
    return getFlowMetrics(missionId);
  }

  replayGraph(events: EvidenceEnvelope[]): KnowledgeGraph {
    return replayPipeline(events).graph;
  }

  replayFull(events: EvidenceEnvelope[]) {
    return replayPipeline(events);
  }

  deriveFacts(events: EvidenceEnvelope[]) {
    return deriveFactsFromEvidence(events);
  }
}

export const evidencePipelineService = new EvidencePipelineService();
