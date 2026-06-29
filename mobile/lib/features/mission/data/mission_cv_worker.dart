import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/spatial_cv/spatial_cv_pipeline.dart';
import '../../../core/spatial_cv/spatial_cv_types.dart';
import '../models/layout_georef_models.dart';
import '../models/pdf_georef_models.dart';
import 'landmark_anchor_service.dart';
import 'layout_georef_math.dart';

/// Serializable boundary ring for isolate return values.
typedef BoundaryRingPoint = ({double x, double y});

/// Arguments for isolate boundary tracing (OCR seed computed on main thread).
class TrackBoundaryJob {
  const TrackBoundaryJob({
    required this.bytes,
    this.blockCenterX,
    this.blockCenterY,
  });

  final Uint8List bytes;
  final double? blockCenterX;
  final double? blockCenterY;
}

class ManualIntelIsolateArgs {
  const ManualIntelIsolateArgs({
    required this.mapBytes,
    required this.layoutPath,
    required this.uvRing,
    required this.controlPoints,
  });

  final Uint8List mapBytes;
  final String layoutPath;
  final List<BoundaryRingPoint> uvRing;
  final List<Map<String, dynamic>> controlPoints;
}

/// Heavy CV boundary trace — run inside [compute].
List<BoundaryRingPoint> runTrackBoundaryJob(TrackBoundaryJob job) {
  UvPoint? blockCenterUv;
  if (job.blockCenterX != null && job.blockCenterY != null) {
    blockCenterUv = UvPoint(job.blockCenterX!, job.blockCenterY!);
  }

  final cv = runSpatialCvPipeline(job.bytes, blockCenterUv: blockCenterUv);
  if (cv.boundaryPolygon.length < 3) return const [];
  return cv.boundaryPolygon.map((p) => (x: p.x, y: p.y)).toList();
}

GeorefControlPoint _controlPointFromJson(Map<String, dynamic> json) => GeorefControlPoint(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      sketchX: (json['sketchX'] as num).toDouble(),
      sketchY: (json['sketchY'] as num).toDouble(),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );

void _validateControlPoints(List<GeorefControlPoint> points) {
  if (points.length < 2) return;
  var maxUvDist = 0.0;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final du = points[j].sketchX - points[i].sketchX;
      final dv = points[j].sketchY - points[i].sketchY;
      maxUvDist = math.max(maxUvDist, math.sqrt(du * du + dv * dv));
    }
  }
  if (maxUvDist < 0.06) {
    throw Exception(
      'Landmarks too close on the PDF map — pick two that are far apart (e.g. church and school).',
    );
  }
}

/// Build mission intelligence off the UI thread after pins are matched.
Map<String, dynamic> buildManualIntelInIsolate(ManualIntelIsolateArgs args) {
  final uvRing = args.uvRing;
  if (uvRing.length < 3) {
    throw Exception('Trace the white HLB boundary first');
  }

  final controlPoints = [
    for (final raw in args.controlPoints) _controlPointFromJson(raw),
  ];
  if (controlPoints.length < kMinGeorefMatchedPins) {
    throw Exception('Match at least $kMinGeorefMatchedPins pins to Google Maps locations');
  }

  _validateControlPoints(controlPoints);

  final aligned = SatelliteAlignMath.alignFromControlPoints(controlPoints, uvRing);
  final affineMatrix = aligned.affineMatrix;

  const boundaryConfidence = 0.92;
  const structuresConfidence = 0.0;
  final overall = (boundaryConfidence * 0.35 + 0.25).clamp(0.0, 1.0);

  const observationTargets = <Map<String, dynamic>>[];

  return {
    'generatedAt': DateTime.now().toIso8601String(),
    'engine': 'spatial_cv',
    'engineVersion': spatialCvVersion,
    'alignment': {
      'autoAligned': true,
      'method': 'manual_pins',
      'qualityPercent': LandmarkAnchorService.qualityPercentFromRms(aligned.rmsErrorMeters),
      'score': aligned.alignmentLabel.toLowerCase().replaceAll(' ', '_'),
      'imageBounds': aligned.imageBounds.toJson(),
      'affineMatrix': affineMatrix,
      'rmsErrorMeters': aligned.rmsErrorMeters.round(),
      'alignmentLabel': aligned.alignmentLabel,
      'controlPoints': args.controlPoints,
    },
    'confidence': {
      'boundary': boundaryConfidence,
      'structures': structuresConfidence,
      'roads': 0.25,
      'landmarks': 0.05,
      'alignment': aligned.rmsErrorMeters < 80 ? 0.9 : 0.6,
      'overall': overall,
    },
    'boundary': {
      'source': 'manual_tracked',
      'confidence': boundaryConfidence,
      'gpsRing': aligned.gpsBoundary.map((p) => p.toJson()).toList(),
      'uvRing': uvRing.map((p) => {'x': p.x, 'y': p.y}).toList(),
    },
    'hypotheses': {
      'observationTargets': observationTargets,
      'roads': const [],
      'landmarks': const [],
      'waterBodies': const [],
      'canalCrossings': const [],
      'vegetationPatches': const [],
    },
    'summary': {
      'observationTargets': observationTargets.length,
      'roadSegments': 0,
      'possibleLandmarks': controlPoints.length,
      'canalCrossings': 0,
      'vegetationPatches': 0,
    },
    'layoutImagePath': args.layoutPath,
  };
}
