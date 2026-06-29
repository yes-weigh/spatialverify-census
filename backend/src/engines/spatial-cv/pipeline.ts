import { detectObservationTargets } from './building-detector.js';
import { detectBoundary } from './boundary-detector.js';
import { detectRoadSegments } from './road-detector.js';
import { detectWaterAndVegetation } from './water-detector.js';
import type { CvExtractionResult } from './types.js';
import { SPATIAL_CV_VERSION } from './types.js';

/**
 * Offline deterministic CV pipeline — OpenCV-style heuristics via sharp pixel analysis.
 * ONNX models can be plugged in via onnx-runner when available.
 */
export async function runSpatialCvPipeline(imageBuffer: Buffer): Promise<CvExtractionResult> {
  const boundary = await detectBoundary(imageBuffer);
  const boundaryUv = boundary.polygon;

  const [buildings, roads, env] = await Promise.all([
    detectObservationTargets(imageBuffer, boundaryUv),
    detectRoadSegments(imageBuffer, boundaryUv),
    detectWaterAndVegetation(imageBuffer, boundaryUv),
  ]);

  const alignment =
    boundary.confidence * 0.5 +
    (buildings.targets.length > 0 ? 0.25 : 0.05) +
    (roads.segments.length > 0 ? 0.15 : 0.05) +
    0.05;

  const overall =
    boundary.confidence * 0.35 +
    buildings.confidence * 0.3 +
    roads.confidence * 0.25 +
    env.landmarkConfidence * 0.1;

  return {
    engine: 'spatial_cv',
    engineVersion: SPATIAL_CV_VERSION,
    boundaryPolygon: boundaryUv,
    observationTargets: buildings.targets,
    roadSegments: roads.segments,
    landmarks: env.landmarks,
    waterBodies: env.waterBodies,
    canalCrossings: env.canalCrossings,
    vegetationPatches: env.vegetationPatches,
    confidence: {
      boundary: Math.round(boundary.confidence * 100) / 100,
      structures: Math.round(buildings.confidence * 100) / 100,
      roads: Math.round(roads.confidence * 100) / 100,
      landmarks: Math.round(env.landmarkConfidence * 100) / 100,
      alignment: Math.round(alignment * 100) / 100,
      overall: Math.round(overall * 100) / 100,
    },
    diagnostics: {
      ...boundary.diagnostics,
      observationTargetCount: buildings.targets.length,
      roadSegmentCount: roads.segments.length,
    },
  };
}
