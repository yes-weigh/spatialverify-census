import { z } from 'zod';
import type { AppendEvidenceInput, EvidenceTypeId } from './types.js';

const evidenceTypeIds = [
  'mission_imported',
  'boundary_accepted',
  'boundary_adjusted',
  'walk_started',
  'breadcrumb_recorded',
  'entered_region',
  'camera_opened',
  'photo_captured',
  'region_confirmed',
  'region_rejected',
  'region_ignored',
  'gap_detected',
  'gap_resolved',
  'building_classified',
  'listing_completed',
  'mission_completed',
  'mission_audited',
  'gps_visit',
] as const satisfies readonly EvidenceTypeId[];

const aggregateTypes = [
  'mission',
  'boundary',
  'observation_region',
  'building',
  'gap',
  'coverage_cell',
  'expectation',
] as const;

export const appendEvidenceBodySchema = z.object({
  aggregateId: z.string().min(1),
  aggregateType: z.enum(aggregateTypes),
  evidenceType: z.enum(evidenceTypeIds),
  schemaVersion: z.string().min(1).default('1'),
  payload: z.record(z.unknown()).default({}),
  occurredAt: z.string().datetime({ offset: true }).optional(),
  device: z
    .object({
      id: z.string().optional(),
      platform: z.string().optional(),
    })
    .optional(),
});

export type AppendEvidenceBody = z.infer<typeof appendEvidenceBodySchema>;

export function toAppendInput(
  missionId: string,
  body: AppendEvidenceBody,
  actorUserId: string
): AppendEvidenceInput {
  return {
    missionId,
    aggregateId: body.aggregateId,
    aggregateType: body.aggregateType,
    evidenceType: body.evidenceType,
    schemaVersion: body.schemaVersion,
    payload: body.payload,
    occurredAt: body.occurredAt ?? new Date().toISOString(),
    actor: { userId: actorUserId },
    device: body.device ?? null,
  };
}

/** Per-type payload validation (extend as catalog grows). */
export function validateEvidencePayload(
  evidenceType: EvidenceTypeId,
  schemaVersion: string,
  payload: Record<string, unknown>
): void {
  if (schemaVersion !== '1') {
    throw new Error(`Unsupported evidence schema version: ${evidenceType}@${schemaVersion}`);
  }

  switch (evidenceType) {
    case 'region_confirmed': {
      if (typeof payload.regionId !== 'string') {
        throw new Error('region_confirmed@1 requires payload.regionId');
      }
      break;
    }
    case 'boundary_accepted':
      break;
    case 'mission_imported': {
      if (!Array.isArray(payload.regions)) {
        throw new Error('mission_imported@1 requires payload.regions array');
      }
      break;
    }
    case 'gps_visit': {
      if (typeof payload.lat !== 'number' || typeof payload.lng !== 'number') {
        throw new Error('gps_visit@1 requires payload.lat and payload.lng');
      }
      break;
    }
    default:
      break;
  }
}
