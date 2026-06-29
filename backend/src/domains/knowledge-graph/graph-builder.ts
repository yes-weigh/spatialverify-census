import type { DomainEvent } from '../domain-events/types.js';
import type { KnowledgeGraph, MissionAggregate } from '../reasoning/reasoning-engine.js';
function bumpMission(graph: KnowledgeGraph): void {
  graph.aggregates.mission.aggregateVersion += 1;
}

/** Apply domain events to graph — sole mutator of aggregate state. */
export function applyDomainEvents(graph: KnowledgeGraph, domainEvents: DomainEvent[]): KnowledgeGraph {
  const next: KnowledgeGraph = JSON.parse(JSON.stringify(graph)) as KnowledgeGraph;

  for (const event of domainEvents) {
    bumpMission(next);

    switch (event.type) {
      case 'RegionPredicted':
        next.aggregates.observationRegions[event.aggregateId] = {
          aggregateType: 'observation_region',
          aggregateId: event.aggregateId,
          aggregateVersion: 1,
          state: 'PREDICTED',
          confidence: (event.payload.confidence as number) ?? 0.5,
        };
        next.aggregates.mission.state = 'PREDICTED';
        break;

      case 'RegionObserved': {
        const region = next.aggregates.observationRegions[event.aggregateId];
        if (region) {
          region.state = 'OBSERVED';
          region.aggregateVersion += 1;
        } else {
          next.aggregates.observationRegions[event.aggregateId] = {
            aggregateType: 'observation_region',
            aggregateId: event.aggregateId,
            aggregateVersion: 1,
            state: 'OBSERVED',
            confidence: 0.5,
          };
        }
        break;
      }

      case 'RegionValidated': {
        const region = next.aggregates.observationRegions[event.aggregateId];
        const buildingId = event.payload.buildingId as string;
        if (region) {
          region.state = 'VALIDATED';
          region.supersededByBuildingId = buildingId;
          region.aggregateVersion += 1;
        }
        break;
      }

      case 'BuildingCreated':
        next.aggregates.buildings[event.aggregateId] = {
          aggregateType: 'building',
          aggregateId: event.aggregateId,
          aggregateVersion: 1,
          state: 'VALIDATED',
          sourceRegionId: event.payload.sourceRegionId as string,
          lat: event.payload.lat as number | undefined,
          lng: event.payload.lng as number | undefined,
        };
        break;

      case 'RegionRejected': {
        const region = next.aggregates.observationRegions[event.aggregateId];
        if (region) {
          region.state = 'REJECTED';
          region.aggregateVersion += 1;
        }
        break;
      }

      case 'RegionIgnored': {
        const region = next.aggregates.observationRegions[event.aggregateId];
        if (region) {
          region.state = 'IGNORED';
          region.aggregateVersion += 1;
        }
        break;
      }

      case 'BoundaryValidated':
        next.aggregates.boundary = {
          aggregateType: 'boundary',
          aggregateId: event.aggregateId,
          aggregateVersion: 1,
          state: 'VALIDATED',
        };
        break;

      case 'MissionProgressChanged':
        break;
    }
  }

  return next;
}

export function initMissionAggregate(): MissionAggregate {
  return { aggregateType: 'mission', aggregateVersion: 0, state: 'UNKNOWN' };
}
