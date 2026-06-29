import 'dart:typed_data';

import 'spatial_cv_boundary.dart';
import 'spatial_cv_image.dart';
import 'spatial_cv_types.dart';

const spatialCvVersion = '1.2.0-mobile';

CvExtractionResult runSpatialCvPipeline(Uint8List imageBytes, {UvPoint? blockCenterUv}) {
  final img = loadRgbImage(imageBytes, maxDim: 1600);
  final boundary = detectBoundary(img, blockCenterUv: blockCenterUv);
  final boundaryUv = boundary.polygon;

  const alignment = 0.35;
  final overall = boundary.confidence * 0.55 + 0.25 * 0.25 + 0.05 * 0.1;

  return CvExtractionResult(
    boundaryPolygon: boundaryUv,
    observationTargets: const [],
    roadSegments: const [],
    landmarks: const [],
    waterBodies: const [],
    canalCrossings: const [],
    vegetationPatches: const [],
    confidence: SpatialConfidence(
      boundary: (boundary.confidence * 100).round() / 100,
      structures: 0,
      roads: 0.25,
      landmarks: 0.05,
      alignment: alignment,
      overall: (overall * 100).round() / 100,
    ),
    diagnostics: {
      ...boundary.diagnostics,
      'observationTargetCount': 0,
      'roadSegmentCount': 0,
    },
  );
}
