export type EvidenceType =
  | 'satellite'
  | 'camera'
  | 'gps_visit'
  | 'enumerator_confirmed'
  | 'photo'
  | 'timestamp';

export interface EvidenceRecord {
  type: EvidenceType;
  at: string;
  confidence?: number;
  source?: string;
  metadata?: Record<string, unknown>;
}

export type TwinObjectKind =
  | 'boundary'
  | 'observation_target'
  | 'road_segment'
  | 'landmark'
  | 'water_body'
  | 'canal_crossing'
  | 'vegetation';

export type TwinObjectStatus = 'hypothesis' | 'observed' | 'confirmed' | 'rejected';

export interface TwinObject {
  id: string;
  kind: TwinObjectKind;
  label: string;
  lat?: number;
  lng?: number;
  status: TwinObjectStatus;
  confidence: number;
  evidence: EvidenceRecord[];
  metadata?: Record<string, unknown>;
}

export interface HlbDigitalTwin {
  ebId: string;
  generatedAt: string;
  engine: 'spatial_cv';
  objects: TwinObject[];
  graphs: {
    roadGraph: { nodeIds: string[]; edges: Array<[string, string]> };
    buildingGraph: { nodeIds: string[]; edges: Array<[string, string]> };
    coverageGraph: { nodes: string[] };
    discoveryGraph: { nodes: string[] };
    evidenceGraph: { nodeIds: string[]; evidenceCount: number };
  };
}

export function satelliteEvidence(at: string, confidence: number): EvidenceRecord {
  return { type: 'satellite', at, confidence, source: 'spatial_cv' };
}

export function buildDigitalTwinFromCv(
  ebId: string,
  extraction: {
    boundaryPolygon: Array<{ x: number; y: number }>;
    observationTargets: Array<{ id: string; label: string; sketchX: number; sketchY: number; confidence: number; lat?: number; lng?: number }>;
    roadSegments: Array<{ id: string; label: string; points: Array<{ lat: number; lng: number }>; confidence: number }>;
    landmarks: Array<{ id: string; label: string; lat: number; lng: number; confidence: number }>;
    waterBodies: Array<{ id: string; label: string; lat: number; lng: number }>;
    canalCrossings: Array<{ id: string; label: string; lat: number; lng: number }>;
    vegetationPatches: Array<{ id: string; label: string; lat: number; lng: number }>;
    boundaryConfidence: number;
  }
): HlbDigitalTwin {
  const at = new Date().toISOString();
  const objects: TwinObject[] = [];

  objects.push({
    id: 'boundary',
    kind: 'boundary',
    label: 'HLB Boundary',
    status: 'hypothesis',
    confidence: extraction.boundaryConfidence,
    evidence: [satelliteEvidence(at, extraction.boundaryConfidence)],
  });

  for (const t of extraction.observationTargets) {
    objects.push({
      id: t.id,
      kind: 'observation_target',
      label: t.label,
      lat: t.lat,
      lng: t.lng,
      status: 'hypothesis',
      confidence: t.confidence,
      evidence: [satelliteEvidence(at, t.confidence)],
    });
  }

  for (const r of extraction.roadSegments) {
    const mid = r.points[Math.floor(r.points.length / 2)];
    objects.push({
      id: r.id,
      kind: 'road_segment',
      label: r.label,
      lat: mid?.lat,
      lng: mid?.lng,
      status: 'hypothesis',
      confidence: r.confidence,
      evidence: [satelliteEvidence(at, r.confidence)],
      metadata: { pointCount: r.points.length },
    });
  }

  for (const l of extraction.landmarks) {
    objects.push({
      id: l.id,
      kind: 'landmark',
      label: l.label,
      lat: l.lat,
      lng: l.lng,
      status: 'hypothesis',
      confidence: l.confidence,
      evidence: [satelliteEvidence(at, l.confidence)],
    });
  }

  const roadIds = extraction.roadSegments.map((r) => r.id);
  const targetIds = extraction.observationTargets.map((t) => t.id);

  return {
    ebId,
    generatedAt: at,
    engine: 'spatial_cv',
    objects,
    graphs: {
      roadGraph: { nodeIds: roadIds, edges: [] },
      buildingGraph: { nodeIds: targetIds, edges: [] },
      coverageGraph: { nodes: roadIds },
      discoveryGraph: { nodes: targetIds },
      evidenceGraph: { nodeIds: objects.map((o) => o.id), evidenceCount: objects.length },
    },
  };
}

export function attachEvidence(obj: TwinObject, record: EvidenceRecord): TwinObject {
  return { ...obj, evidence: [...obj.evidence, record] };
}
