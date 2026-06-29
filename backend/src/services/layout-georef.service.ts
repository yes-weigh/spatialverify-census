import { missionRepository } from '../repositories/mission.repository.js';
import { layoutGeorefRepository } from '../repositories/layout-georef.repository.js';
import { hlbBoundaryRepository } from '../repositories/hlb-boundary.repository.js';
import { storageService } from './storage.service.js';
import { extractLayoutFeatures } from './gemini-vision.service.js';
import { runSpatialCvPipeline } from '../engines/spatial-cv/pipeline.js';
import {
  alignmentQuality,
  applyAffine,
  computeAffineTransform,
  sketchPolygonArea,
  transformSketchBoundary,
  type ControlPoint,
} from '../utils/affine-transform.js';
import { computeNorthWestStartPoint } from '../utils/polygon-utils.js';
import {
  alignmentQualityFromBounds,
  imageUvToLatLng,
  polygonAreaSqMeters,
} from '../utils/satellite-registration.js';
import type { GeoJSONPolygon } from '../types/hlb-boundary.js';
import type { GeorefValidation, GpsPoint, ImageBounds, LayoutControlPoint } from '../types/layout-georef.js';

const MIN_AREA_SQ_METERS = 5000;

export async function getLayoutGeorefSession(ebId: string, withUrl = true) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session) return null;
  if (withUrl) {
    const key = session.previewMapKey ?? session.uploadedMapKey;
    const layoutImageUrl = await storageService.getPresignedDownloadUrl(key);
    return { ...session, layoutImageUrl };
  }
  return session;
}

export async function uploadLayoutMap(
  ebId: string,
  buffer: Buffer,
  mimeType: string,
  filename: string,
  createdBy: string,
  previewBuffer?: Buffer
) {
  const key = storageService.generateKey(`layout-maps/${ebId}`, filename);
  await storageService.upload(key, buffer, mimeType);
  await missionRepository.updateLayoutImage(ebId, key, mimeType);

  let previewKey: string | undefined;
  if (previewBuffer) {
    previewKey = storageService.generateKey(`layout-maps/${ebId}`, 'preview.jpg');
    await storageService.upload(previewKey, previewBuffer, 'image/jpeg');
  }

  const session = await layoutGeorefRepository.upsertUpload({
    ebId,
    uploadedMapKey: key,
    previewMapKey: previewKey,
    mimeType,
    createdBy,
  });

  const layoutImageUrl = await storageService.getPresignedDownloadUrl(previewKey ?? key);
  return { ...session, layoutImageUrl };
}

export async function extractLandmarks(ebId: string) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session) throw new Error('No layout map uploaded');

  const key = session.previewMapKey ?? session.uploadedMapKey;
  const url = await storageService.getPresignedDownloadUrl(key);
  const res = await fetch(url);
  const buffer = Buffer.from(await res.arrayBuffer());
  const base64 = buffer.toString('base64');
  const mime = session.previewMapKey ? 'image/jpeg' : session.mimeType;

  const extraction = await extractLayoutFeatures(base64, mime.startsWith('image/') ? mime : 'image/jpeg');
  await layoutGeorefRepository.updateSession(ebId, {
    aiSuggestions: extraction as unknown as Record<string, unknown>,
    landmarks: extraction.landmarks,
    roads: extraction.roads,
    waterBodies: extraction.waterBodies,
    status: 'aligning',
  });

  return extraction;
}

export async function saveControlPoints(ebId: string, points: LayoutControlPoint[]) {
  await layoutGeorefRepository.updateSession(ebId, {
    controlPoints: points,
    status: 'aligning',
  });
  return points;
}

export async function saveSketchBoundary(ebId: string, boundary: Array<{ x: number; y: number }>) {
  await layoutGeorefRepository.updateSession(ebId, { sketchBoundary: boundary });
  return boundary;
}

export async function saveImageBounds(ebId: string, bounds: ImageBounds) {
  const score = alignmentQualityFromBounds(bounds);
  await layoutGeorefRepository.updateSession(ebId, {
    imageBounds: bounds,
    alignmentScore: score,
    alignmentMode: 'satellite_registration',
    status: 'aligning',
  });
  return { bounds, alignmentScore: score };
}

export async function saveGpsBoundary(ebId: string, ring: GpsPoint[]) {
  const area = polygonAreaSqMeters(ring);
  let boundaryPolygon: GeoJSONPolygon | undefined;
  if (ring.length >= 3) {
    const closed = [...ring, ring[0]];
    boundaryPolygon = {
      type: 'Polygon',
      coordinates: [closed.map((p) => [p.lng, p.lat])],
    };
  }
  await layoutGeorefRepository.updateSession(ebId, {
    gpsBoundary: ring,
    boundaryPolygon,
    polygonAreaSqMeters: area,
    status: 'validated',
  });
  return { ring, areaSqMeters: area, boundaryPolygon };
}

async function loadMapImageBuffer(session: { previewMapKey: string | null; uploadedMapKey: string; mimeType: string }) {
  const key = session.previewMapKey ?? session.uploadedMapKey;
  const url = await storageService.getPresignedDownloadUrl(key);
  const res = await fetch(url);
  const buffer = Buffer.from(await res.arrayBuffer());
  const mime = session.previewMapKey ? 'image/jpeg' : session.mimeType;
  return { buffer, mime: mime.startsWith('image/') ? mime : 'image/jpeg' };
}

export async function detectSatelliteStructures(ebId: string) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session) throw new Error('No layout map uploaded');

  const { buffer } = await loadMapImageBuffer(session);
  const cv = await runSpatialCvPipeline(buffer);
  const bounds = session.imageBounds;

  const observationTargets = bounds
    ? cv.observationTargets.map((s) => {
        const gps = imageUvToLatLng(s.sketchX, s.sketchY, bounds);
        return { ...s, label: 'Observation target', lat: gps.lat, lng: gps.lng };
      })
    : cv.observationTargets.map((s) => ({ ...s, label: 'Observation target' }));

  let gpsBoundary: GpsPoint[] | undefined;
  if (bounds && cv.boundaryPolygon.length >= 3) {
    gpsBoundary = cv.boundaryPolygon.map((p) => imageUvToLatLng(p.x, p.y, bounds));
  }

  const patch: Parameters<typeof layoutGeorefRepository.updateSession>[1] = {
    potentialStructures: observationTargets,
    aiSuggestions: { engine: 'spatial_cv', diagnostics: cv.diagnostics },
    roads: cv.roadSegments,
    waterBodies: cv.waterBodies,
    status: 'aligning',
  };

  if (gpsBoundary && gpsBoundary.length >= 3) {
    const area = polygonAreaSqMeters(gpsBoundary);
    const closed = [...gpsBoundary, gpsBoundary[0]];
    patch.gpsBoundary = gpsBoundary;
    patch.polygonAreaSqMeters = area;
    patch.boundaryPolygon = {
      type: 'Polygon',
      coordinates: [closed.map((p) => [p.lng, p.lat])],
    };
  }

  await layoutGeorefRepository.updateSession(ebId, patch);

  return {
    observationTargets,
    potentialStructures: observationTargets,
    gpsBoundary: gpsBoundary ?? session.gpsBoundary,
    confidence: cv.confidence,
  };
}

export async function computeTransform(ebId: string) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session || session.controlPoints.length < 3) {
    throw new Error('At least 3 control points required');
  }

  const { matrix, rmsErrorMeters } = computeAffineTransform(session.controlPoints as ControlPoint[]);
  const score = alignmentQuality(rmsErrorMeters);

  let boundaryPolygon: GeoJSONPolygon | null = null;
  let polygonAreaSqMeters: number | null = null;

  if (session.sketchBoundary.length >= 3) {
    const gpsRing = transformSketchBoundary(matrix, session.sketchBoundary);
    const closed = [...gpsRing, gpsRing[0]];
    boundaryPolygon = {
      type: 'Polygon',
      coordinates: [closed.map((p) => [p.lng, p.lat])],
    };
    polygonAreaSqMeters = estimatePolygonArea(gpsRing);
  }

  await layoutGeorefRepository.updateSession(ebId, {
    affineMatrix: matrix,
    boundaryPolygon: boundaryPolygon ?? undefined,
    rmsErrorMeters,
    alignmentScore: score,
    polygonAreaSqMeters: polygonAreaSqMeters ?? undefined,
    status: 'validated',
  });

  return { matrix, rmsErrorMeters, alignmentScore: score, boundaryPolygon };
}

function estimatePolygonArea(ring: Array<{ lat: number; lng: number }>): number {
  if (ring.length < 3) return 0;
  const center = ring.reduce((a, p) => ({ lat: a.lat + p.lat, lng: a.lng + p.lng }), { lat: 0, lng: 0 });
  center.lat /= ring.length;
  center.lng /= ring.length;
  const mPerDegLat = 111320;
  const mPerDegLng = 111320 * Math.cos((center.lat * Math.PI) / 180);
  let area = 0;
  for (let i = 0; i < ring.length; i++) {
    const j = (i + 1) % ring.length;
    const xi = (ring[i].lng - center.lng) * mPerDegLng;
    const yi = (ring[i].lat - center.lat) * mPerDegLat;
    const xj = (ring[j].lng - center.lng) * mPerDegLng;
    const yj = (ring[j].lat - center.lat) * mPerDegLat;
    area += xi * yj - xj * yi;
  }
  return Math.abs(area) / 2;
}

export function validateGeoref(session: {
  alignmentMode?: 'satellite_registration' | 'landmark';
  controlPoints: LayoutControlPoint[];
  sketchBoundary: Array<{ x: number; y: number }>;
  gpsBoundary?: GpsPoint[];
  imageBounds?: ImageBounds | null;
  potentialStructures?: Array<{ id: string }>;
  rmsErrorMeters: number | null;
  polygonAreaSqMeters: number | null;
  alignmentScore?: string | null;
}): GeorefValidation {
  const warnings: string[] = [];

  if (session.alignmentMode === 'satellite_registration') {
    const polygonClosed = (session.gpsBoundary?.length ?? 0) >= 3;
    if (!polygonClosed) warnings.push('Mark at least 3 boundary corners on the aligned map');

    const areaAboveMinimum = (session.polygonAreaSqMeters ?? 0) >= MIN_AREA_SQ_METERS;
    if (!areaAboveMinimum) warnings.push('GPS boundary area seems too small — verify alignment');

    if (!session.imageBounds) warnings.push('Image alignment not saved — adjust overlay on satellite map');

    const alignmentScore = (session.alignmentScore as GeorefValidation['alignmentScore']) ?? 'good';

    return {
      polygonClosed,
      areaAboveMinimum,
      rmsErrorMeters: 0,
      alignmentScore,
      controlPointCount: 0,
      potentialStructureCount: session.potentialStructures?.length ?? 0,
      warnings,
    };
  }

  const sketchArea = sketchPolygonArea(session.sketchBoundary);
  const polygonClosed = session.sketchBoundary.length >= 3 && sketchArea > 0.001;
  if (!polygonClosed) warnings.push('Boundary polygon is not closed — mark at least 3 corners on the layout map');

  const areaAboveMinimum = (session.polygonAreaSqMeters ?? 0) >= MIN_AREA_SQ_METERS;
  if (!areaAboveMinimum) warnings.push('GPS boundary area seems too small — verify alignment');

  const rms = session.rmsErrorMeters ?? 999;
  const alignmentScore = alignmentQuality(rms);
  if (alignmentScore === 'needs_review') {
    warnings.push('Control point alignment error is high — add more points or reposition');
  }

  return {
    polygonClosed,
    areaAboveMinimum,
    rmsErrorMeters: rms,
    alignmentScore,
    controlPointCount: session.controlPoints.length,
    potentialStructureCount: 0,
    warnings,
  };
}

export async function finalizeGeoref(ebId: string, userId: string) {
  const session = await layoutGeorefRepository.findByEbId(ebId);
  if (!session) throw new Error('No georef session');

  let boundaryPolygon = session.boundaryPolygon;
  if (session.alignmentMode === 'satellite_registration') {
    if (!session.gpsBoundary || session.gpsBoundary.length < 3) {
      throw new Error('Mark GPS boundary on aligned satellite map first');
    }
    if (!boundaryPolygon) {
      const closed = [...session.gpsBoundary, session.gpsBoundary[0]];
      boundaryPolygon = {
        type: 'Polygon',
        coordinates: [closed.map((p) => [p.lng, p.lat])],
      };
    }
  } else if (!boundaryPolygon || !session.affineMatrix) {
    throw new Error('Run compute transform first with a valid boundary');
  }

  const validation = validateGeoref(session);
  if (!validation.polygonClosed) throw new Error('Boundary polygon not closed');

  const block = await missionRepository.findBlockById(ebId);
  if (!block) throw new Error('EB not found');

  const ring = boundaryPolygon!.coordinates[0];
  const start = computeNorthWestStartPoint(ring);

  const boundary = await hlbBoundaryRepository.upsertBoundary({
    ebId,
    hlbCode: block.eb_code as string,
    name: block.name as string | undefined,
    geoJson: boundaryPolygon!,
    startLat: start.lat,
    startLng: start.lng,
    source: 'layout_map',
  });

  await layoutGeorefRepository.updateSession(ebId, {
    status: 'finalized',
    finalizedAt: new Date().toISOString(),
  });

  await hlbBoundaryRepository.upsertAudit(ebId, {
    enumeratorId: userId,
    outsideBoundaryDiscoveries: [],
  });

  return { boundary, validation, session };
}

export function transformLandmarks(
  matrix: number[],
  landmarks: Array<{ label: string; sketchX: number; sketchY: number }>
) {
  return landmarks.map((l) => {
    const gps = applyAffine(matrix, l.sketchX, l.sketchY);
    return { ...l, ...gps };
  });
}
