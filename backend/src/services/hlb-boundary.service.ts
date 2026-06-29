import { missionRepository } from '../repositories/mission.repository.js';
import { hlbBoundaryRepository } from '../repositories/hlb-boundary.repository.js';
import type { GeoJSONPolygon, HlbBoundary } from '../types/hlb-boundary.js';
import { computeNorthWestStartPoint, exteriorRing, parseGeoJsonPolygon } from '../utils/polygon-utils.js';

export async function listHlbBoundaries(projectId?: string) {
  return hlbBoundaryRepository.list(projectId);
}

export async function getHlbBoundary(id: string) {
  return hlbBoundaryRepository.findById(id);
}

export async function getHlbBoundaryMission(id: string) {
  return hlbBoundaryRepository.getMissionPackage(id);
}

export async function getHlbBoundaryMissionByEbId(ebId: string) {
  return hlbBoundaryRepository.getMissionPackageByEbId(ebId);
}

export interface ImportHlbBoundaryInput {
  projectId: string;
  hlbCode: string;
  name?: string;
  boundary?: GeoJSONPolygon;
  wkt?: string;
  northDescription?: string;
  southDescription?: string;
  eastDescription?: string;
  westDescription?: string;
  assignedEnumeratorId?: string;
  createdBy: string;
}

export async function importHlbBoundary(input: ImportHlbBoundaryInput): Promise<HlbBoundary> {
  let existingEb = await missionRepository.findBlockByProjectAndCode(input.projectId, input.hlbCode);
  if (!existingEb) {
    existingEb = await missionRepository.createBlock({
      projectId: input.projectId,
      ebCode: input.hlbCode,
      name: input.name,
      assignedEnumeratorId: input.assignedEnumeratorId,
      createdBy: input.createdBy,
    });
  }

  const ebId = existingEb.id as string;

  if (input.wkt) {
    return hlbBoundaryRepository.importFromWkt(ebId, input.hlbCode, input.wkt, {
      name: input.name,
      northDescription: input.northDescription,
      southDescription: input.southDescription,
      eastDescription: input.eastDescription,
      westDescription: input.westDescription,
    });
  }

  const geoJson = parseGeoJsonPolygon(input.boundary);
  const ring = exteriorRing(geoJson);
  const start = computeNorthWestStartPoint(ring);

  return hlbBoundaryRepository.upsertBoundary({
    ebId,
    hlbCode: input.hlbCode,
    name: input.name,
    geoJson,
    startLat: start.lat,
    startLng: start.lng,
    northDescription: input.northDescription,
    southDescription: input.southDescription,
    eastDescription: input.eastDescription,
    westDescription: input.westDescription,
  });
}

export async function recordBoundaryAuditEvent(
  ebId: string,
  event: 'entered' | 'left' | 'start_reached' | 'discovery_started',
  enumeratorId?: string
) {
  const now = new Date().toISOString();
  const patch: Record<string, string | undefined> = { enumeratorId };
  switch (event) {
    case 'entered':
      patch.enteredBoundaryAt = now;
      break;
    case 'left':
      patch.leftBoundaryAt = now;
      break;
    case 'start_reached':
      patch.startPointReachedAt = now;
      break;
    case 'discovery_started':
      patch.discoveryStartedAt = now;
      break;
  }
  await hlbBoundaryRepository.upsertAudit(ebId, patch);
}
