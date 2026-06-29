import { layoutGeorefRepository } from '../repositories/layout-georef.repository.js';
import { storageService } from './storage.service.js';
import { runSpatialCvPipeline } from '../engines/spatial-cv/pipeline.js';
import {
  boundsFromCenter,
  imageUvToLatLng,
  polygonAreaSqMeters,
  shiftBounds,
} from '../utils/satellite-registration.js';
import { buildDigitalTwinFromCv } from '../types/digital-twin.js';
import type { GeoJSONPolygon } from '../types/hlb-boundary.js';
import type { GpsPoint, ImageBounds } from '../types/layout-georef.js';
import type { MissionIntelligence, SpatialConfidence } from '../types/mission-intelligence.js';

const M_PER_DEG_LAT = 111320;

function autoAlignFromBoundary(
  boundaryUv: Array<{ x: number; y: number }>,
  seedLat: number,
  seedLng: number
): { imageBounds: ImageBounds; gpsBoundary: GpsPoint[] } {
  const cx = boundaryUv.reduce((a, p) => a + p.x, 0) / boundaryUv.length;
  const cy = boundaryUv.reduce((a, p) => a + p.y, 0) / boundaryUv.length;
  const minX = Math.min(...boundaryUv.map((p) => p.x));
  const maxX = Math.max(...boundaryUv.map((p) => p.x));
  const minY = Math.min(...boundaryUv.map((p) => p.y));
  const maxY = Math.max(...boundaryUv.map((p) => p.y));
  const spanX = Math.max(maxX - minX, 0.12);
  const spanY = Math.max(maxY - minY, 0.12);
  const maxSpan = Math.max(spanX, spanY);
  const imageSizeM = (550 / maxSpan) * 1.25;
  const aspect = spanY / spanX;

  let bounds = boundsFromCenter(seedLat, seedLng, imageSizeM, imageSizeM * aspect);
  const centroidGps = imageUvToLatLng(cx, cy, bounds);
  const dNorthM = (seedLat - centroidGps.lat) * M_PER_DEG_LAT;
  const dEastM = (seedLng - centroidGps.lng) * M_PER_DEG_LAT * Math.cos((seedLat * Math.PI) / 180);
  bounds = shiftBounds(bounds, dNorthM, dEastM, seedLat);

  const gpsBoundary = boundaryUv.map((p) => imageUvToLatLng(p.x, p.y, bounds));
  return { imageBounds: bounds, gpsBoundary };
}

function scoreFromConfidence(c: SpatialConfidence): 'excellent' | 'good' | 'needs_review' {
  const pct = Math.round(c.overall * 100);
  if (pct >= 85) return 'excellent';
  if (pct >= 65) return 'good';
  return 'needs_review';
}

export async function generateMissionIntelligence(
  ebId: string,
  seedLat: number,
  seedLng: number
): Promise<MissionIntelligence> {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session) throw new Error('No officer map uploaded');

  const key = session.previewMapKey ?? session.uploadedMapKey;
  const url = await storageService.getPresignedDownloadUrl(key);
  const res = await fetch(url);
  const buffer = Buffer.from(await res.arrayBuffer());

  const cv = await runSpatialCvPipeline(buffer);
  const boundaryUv = cv.boundaryPolygon;

  if (boundaryUv.length < 3) {
    throw new Error('Could not detect HLB boundary on officer map — use Adjust to mark manually');
  }

  const { imageBounds, gpsBoundary } = autoAlignFromBoundary(boundaryUv, seedLat, seedLng);
  const toGps = (u: number, v: number) => imageUvToLatLng(u, v, imageBounds);

  const observationTargets = cv.observationTargets.map((s) => {
    const gps = toGps(s.sketchX, s.sketchY);
    return { ...s, label: 'Observation target', lat: gps.lat, lng: gps.lng };
  });

  const landmarks = cv.landmarks.map((l, i) => {
    const gps = toGps(l.sketchX, l.sketchY);
    return {
      id: l.id ?? `lm${i + 1}`,
      label: l.label,
      lat: gps.lat,
      lng: gps.lng,
      confidence: l.confidence,
    };
  });

  const roads = cv.roadSegments.map((r, i) => ({
    id: r.id ?? `rd${i + 1}`,
    label: r.label,
    points: r.points.map((p) => {
      const gps = toGps(p.x, p.y);
      return { lat: gps.lat, lng: gps.lng };
    }),
    confidence: r.confidence,
  }));

  const waterBodies = cv.waterBodies.map((w, i) => {
    const gps = toGps(w.sketchX, w.sketchY);
    return { id: `w${i + 1}`, label: w.label, lat: gps.lat, lng: gps.lng };
  });

  const canalCrossings = cv.canalCrossings.map((c, i) => {
    const gps = toGps(c.sketchX, c.sketchY);
    return { id: `cc${i + 1}`, label: c.label, lat: gps.lat, lng: gps.lng };
  });

  const vegetationPatches = cv.vegetationPatches.map((v, i) => {
    const gps = toGps(v.sketchX, v.sketchY);
    return { id: `veg${i + 1}`, label: v.label, lat: gps.lat, lng: gps.lng };
  });

  const confidence: SpatialConfidence = cv.confidence;
  const qualityPercent = Math.round(confidence.overall * 100);
  const score = scoreFromConfidence(confidence);

  const digitalTwin = buildDigitalTwinFromCv(ebId, {
    boundaryPolygon: boundaryUv,
    observationTargets,
    roadSegments: roads,
    landmarks,
    waterBodies,
    canalCrossings,
    vegetationPatches,
    boundaryConfidence: confidence.boundary,
  });

  const intelligence: MissionIntelligence = {
    generatedAt: new Date().toISOString(),
    engine: 'spatial_cv',
    engineVersion: cv.engineVersion,
    alignment: { autoAligned: true, qualityPercent, score, imageBounds },
    confidence,
    boundary: {
      source: 'cv_detected',
      confidence: confidence.boundary,
      gpsRing: gpsBoundary,
      uvRing: boundaryUv,
    },
    hypotheses: { observationTargets, roads, landmarks, waterBodies, canalCrossings, vegetationPatches },
    summary: {
      observationTargets: observationTargets.length,
      roadSegments: roads.length,
      possibleLandmarks: landmarks.length,
      canalCrossings: canalCrossings.length,
      vegetationPatches: vegetationPatches.length,
    },
    digitalTwin,
  };

  const area = polygonAreaSqMeters(gpsBoundary);
  const closed = [...gpsBoundary, gpsBoundary[0]];
  const boundaryPolygon: GeoJSONPolygon = {
    type: 'Polygon',
    coordinates: [closed.map((p) => [p.lng, p.lat])],
  };

  await layoutGeorefRepository.updateSession(ebId, {
    missionIntelligence: intelligence as unknown as Record<string, unknown>,
    alignmentQualityPercent: qualityPercent,
    imageBounds,
    gpsBoundary,
    potentialStructures: observationTargets,
    boundaryPolygon,
    polygonAreaSqMeters: area,
    alignmentScore: score,
    alignmentMode: 'satellite_registration',
    roads,
    landmarks,
    waterBodies,
    aiSuggestions: { engine: 'spatial_cv', diagnostics: cv.diagnostics },
    status: 'validated',
  });

  return intelligence;
}

export async function getMissionIntelligence(ebId: string): Promise<MissionIntelligence | null> {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  return (session?.missionIntelligence as unknown as MissionIntelligence | null) ?? null;
}

export async function confirmMissionIntelligence(ebId: string) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session?.missionIntelligence) throw new Error('Generate mission intelligence first');
  if (!session.gpsBoundary || session.gpsBoundary.length < 3) {
    throw new Error('Boundary not ready');
  }
  await layoutGeorefRepository.updateSession(ebId, { status: 'validated' });
  return session.missionIntelligence as unknown as MissionIntelligence;
}
