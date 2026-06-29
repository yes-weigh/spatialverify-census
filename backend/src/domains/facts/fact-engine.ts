import type { EvidenceEnvelope } from '../evidence/types.js';

/** Ephemeral deterministic artifacts — not persisted long-term; regenerated from evidence on replay. */
export type FactType =
  | 'RegionPredicted'
  | 'VisitedRegion'
  | 'StructurePresent'
  | 'StructureAbsent'
  | 'RegionIgnored'
  | 'BoundaryAccepted'
  | 'PhotoCaptured';

export interface Fact {
  type: FactType;
  missionId: string;
  aggregateId: string;
  derivedFromEvidenceId: string;
  occurredAt: string;
  payload: Record<string, unknown>;
}

/** Pure function: evidence → facts (compiler tokens). */
export function deriveFactsFromEvidence(events: EvidenceEnvelope[]): Fact[] {
  const facts: Fact[] = [];

  for (const event of events) {
    const key = `${event.evidenceType}@${event.schemaVersion}`;

    switch (key) {
      case 'mission_imported@1': {
        const regions = (event.payload.regions as Array<{ id: string; confidence?: number }>) ?? [];
        for (const region of regions) {
          facts.push({
            type: 'RegionPredicted',
            missionId: event.missionId,
            aggregateId: region.id,
            derivedFromEvidenceId: event.id,
            occurredAt: event.occurredAt,
            payload: { confidence: region.confidence ?? 0.5 },
          });
        }
        break;
      }
      case 'boundary_accepted@1':
        facts.push({
          type: 'BoundaryAccepted',
          missionId: event.missionId,
          aggregateId: event.aggregateId,
          derivedFromEvidenceId: event.id,
          occurredAt: event.occurredAt,
          payload: event.payload,
        });
        break;
      case 'gps_visit@1':
      case 'entered_region@1':
        facts.push({
          type: 'VisitedRegion',
          missionId: event.missionId,
          aggregateId: (event.payload.regionId as string) ?? event.aggregateId,
          derivedFromEvidenceId: event.id,
          occurredAt: event.occurredAt,
          payload: {
            lat: event.payload.lat,
            lng: event.payload.lng,
          },
        });
        break;
      case 'region_confirmed@1':
        facts.push({
          type: 'StructurePresent',
          missionId: event.missionId,
          aggregateId: event.payload.regionId as string,
          derivedFromEvidenceId: event.id,
          occurredAt: event.occurredAt,
          payload: {
            lat: event.payload.lat,
            lng: event.payload.lng,
            photoHash: event.payload.photoHash,
          },
        });
        if (event.payload.photoHash) {
          facts.push({
            type: 'PhotoCaptured',
            missionId: event.missionId,
            aggregateId: event.payload.regionId as string,
            derivedFromEvidenceId: event.id,
            occurredAt: event.occurredAt,
            payload: { photoHash: event.payload.photoHash },
          });
        }
        break;
      case 'region_rejected@1':
        facts.push({
          type: 'StructureAbsent',
          missionId: event.missionId,
          aggregateId: event.payload.regionId as string,
          derivedFromEvidenceId: event.id,
          occurredAt: event.occurredAt,
          payload: event.payload,
        });
        break;
      case 'region_ignored@1':
        facts.push({
          type: 'RegionIgnored',
          missionId: event.missionId,
          aggregateId: event.payload.regionId as string,
          derivedFromEvidenceId: event.id,
          occurredAt: event.occurredAt,
          payload: event.payload,
        });
        break;
      default:
        break;
    }
  }

  return facts;
}
