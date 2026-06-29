class UvPoint {
  const UvPoint(this.x, this.y);
  final double x;
  final double y;
}

class CvDetection {
  CvDetection({
    required this.id,
    required this.label,
    required this.sketchX,
    required this.sketchY,
    this.confidence = 0.5,
  });

  final String id;
  final String label;
  final double sketchX;
  final double sketchY;
  final double confidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'sketchX': sketchX,
        'sketchY': sketchY,
        'confidence': confidence,
      };
}

class SpatialConfidence {
  const SpatialConfidence({
    required this.boundary,
    required this.structures,
    required this.roads,
    required this.landmarks,
    required this.alignment,
    required this.overall,
  });

  final double boundary;
  final double structures;
  final double roads;
  final double landmarks;
  final double alignment;
  final double overall;

  Map<String, dynamic> toJson() => {
        'boundary': boundary,
        'structures': structures,
        'roads': roads,
        'landmarks': landmarks,
        'alignment': alignment,
        'overall': overall,
      };
}

class CvExtractionResult {
  CvExtractionResult({
    required this.boundaryPolygon,
    required this.observationTargets,
    required this.roadSegments,
    required this.landmarks,
    required this.waterBodies,
    required this.canalCrossings,
    required this.vegetationPatches,
    required this.confidence,
    this.diagnostics = const {},
  });

  final List<UvPoint> boundaryPolygon;
  final List<CvDetection> observationTargets;
  final List<Map<String, dynamic>> roadSegments;
  final List<CvDetection> landmarks;
  final List<Map<String, dynamic>> waterBodies;
  final List<Map<String, dynamic>> canalCrossings;
  final List<Map<String, dynamic>> vegetationPatches;
  final SpatialConfidence confidence;
  final Map<String, dynamic> diagnostics;
}
