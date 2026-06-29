import type { Fact } from '../facts/fact-engine.js';
import type { DomainEvent } from '../domain-events/types.js';
import type { KnowledgeGraph } from './reasoning-engine.js';

/** Pure: one fact + graph context → domain events (consequences). */
export function emitDomainEventsFromFact(fact: Fact, graph: KnowledgeGraph): DomainEvent[] {
  const base = {
    missionId: fact.missionId,
    occurredAt: fact.occurredAt,
    derivedFromEvidenceId: fact.derivedFromEvidenceId,
    evidenceSequenceNum: 0,
    payload: fact.payload,
  };

  const events: DomainEvent[] = [];
  const progress = (): DomainEvent => ({
    ...base,
    type: 'MissionProgressChanged',
    aggregateId: fact.missionId,
    aggregateType: 'mission',
    payload: {
      trigger: fact.type,
      validatedBuildings: Object.values(graph.aggregates.buildings).filter(
        (b) => b.state === 'VALIDATED'
      ).length,
      regionCount: Object.keys(graph.aggregates.observationRegions).length,
    },
  });

  switch (fact.type) {
    case 'RegionPredicted':
      events.push({
        ...base,
        type: 'RegionPredicted',
        aggregateId: fact.aggregateId,
        aggregateType: 'observation_region',
        payload: { confidence: fact.payload.confidence },
      });
      events.push(progress());
      break;

    case 'VisitedRegion': {
      const region = graph.aggregates.observationRegions[fact.aggregateId];
      if (!region || region.state === 'PREDICTED') {
        events.push({
          ...base,
          type: 'RegionObserved',
          aggregateId: fact.aggregateId,
          aggregateType: 'observation_region',
          payload: { lat: fact.payload.lat, lng: fact.payload.lng },
        });
        events.push(progress());
      }
      break;
    }

    case 'StructurePresent': {
      const buildingId = `building-${fact.aggregateId}`;
      events.push({
        ...base,
        type: 'RegionValidated',
        aggregateId: fact.aggregateId,
        aggregateType: 'observation_region',
        payload: { buildingId },
      });
      events.push({
        ...base,
        type: 'BuildingCreated',
        aggregateId: buildingId,
        aggregateType: 'building',
        payload: {
          sourceRegionId: fact.aggregateId,
          lat: fact.payload.lat,
          lng: fact.payload.lng,
        },
      });
      events.push(progress());
      break;
    }

    case 'StructureAbsent':
      events.push({
        ...base,
        type: 'RegionRejected',
        aggregateId: fact.aggregateId,
        aggregateType: 'observation_region',
        payload: fact.payload,
      });
      events.push(progress());
      break;

    case 'RegionIgnored':
      events.push({
        ...base,
        type: 'RegionIgnored',
        aggregateId: fact.aggregateId,
        aggregateType: 'observation_region',
        payload: fact.payload,
      });
      events.push(progress());
      break;

    case 'BoundaryAccepted':
      events.push({
        ...base,
        type: 'BoundaryValidated',
        aggregateId: fact.aggregateId,
        aggregateType: 'boundary',
        payload: fact.payload,
      });
      events.push(progress());
      break;

    default:
      break;
  }

  return events;
}
