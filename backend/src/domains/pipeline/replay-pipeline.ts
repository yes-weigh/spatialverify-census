import { deriveFactsFromEvidence } from '../facts/fact-engine.js';
import type { EvidenceEnvelope } from '../evidence/types.js';
import { FACT_ENGINE_VERSION, REASONING_ENGINE_VERSION } from '../evidence/types.js';
import type { DomainEvent } from '../domain-events/types.js';
import { applyDomainEvents, initMissionAggregate } from '../knowledge-graph/graph-builder.js';
import { emitDomainEventsFromFact } from '../reasoning/emit-domain-events.js';
import { emptyKnowledgeGraph, type KnowledgeGraph } from '../reasoning/reasoning-engine.js';
import { recordFlowMetrics } from '../metrics/flow-metrics.js';

export interface ReplayPipelineResult {
  graph: KnowledgeGraph;
  domainEvents: DomainEvent[];
  factsCount: number;
}

/**
 * Evidence → Facts (ephemeral) → Reasoning (domain events) → Graph Builder.
 * Single deterministic replay path used by all projections.
 */
export function replayPipeline(events: EvidenceEnvelope[]): ReplayPipelineResult {
  const missionId = events[0]?.missionId ?? '';
  let graph = emptyKnowledgeGraph(missionId);
  graph.aggregates.mission = initMissionAggregate();

  const facts = deriveFactsFromEvidence(events);
  const factEvidenceSeq = new Map<string, number>();
  for (const event of events) {
    factEvidenceSeq.set(event.id, event.sequenceNum);
  }

  const domainEvents: DomainEvent[] = [];

  for (const fact of facts) {
    const emitted = emitDomainEventsFromFact(fact, graph).map((de) => ({
      ...de,
      evidenceSequenceNum: factEvidenceSeq.get(fact.derivedFromEvidenceId) ?? 0,
    }));
    domainEvents.push(...emitted);
    graph = applyDomainEvents(graph, emitted);
    recordFlowMetrics(graph.missionId, fact, emitted, events);
  }

  const lastSeq = events.length > 0 ? events[events.length - 1].sequenceNum : 0;
  const builtAt = events.length > 0 ? events[events.length - 1].occurredAt : graph.meta.builtAt;
  graph.meta = {
    factEngineVersion: FACT_ENGINE_VERSION,
    reasoningEngineVersion: REASONING_ENGINE_VERSION,
    lastEvidenceSequence: lastSeq,
    builtAt,
  };

  return { graph, domainEvents, factsCount: facts.length };
}

export function buildKnowledgeGraphFromEvidence(events: EvidenceEnvelope[]): KnowledgeGraph {
  return replayPipeline(events).graph;
}
