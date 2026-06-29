import '../data/layout_georef_math.dart';
import '../data/satellite_align_math.dart';

export '../data/layout_georef_math.dart' show GeorefControlPoint;
export '../data/satellite_align_math.dart' show ImageBounds, SatelliteAlignMath;

class SketchPoint {
  const SketchPoint(this.x, this.y);
  final double x;
  final double y;
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory SketchPoint.fromJson(Map<String, dynamic> json) =>
      SketchPoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

class GpsPoint {
  const GpsPoint(this.lat, this.lng);
  final double lat;
  final double lng;
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory GpsPoint.fromJson(Map<String, dynamic> json) =>
      GpsPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
}

class PotentialStructure {
  PotentialStructure({
    required this.id,
    required this.label,
    required this.sketchX,
    required this.sketchY,
    this.lat,
    this.lng,
    this.confidence = 0.5,
  });

  final String id;
  final String label;
  final double sketchX;
  final double sketchY;
  final double? lat;
  final double? lng;
  final double confidence;

  factory PotentialStructure.fromJson(Map<String, dynamic> json) => PotentialStructure(
        id: json['id'] as String? ?? 's1',
        label: json['label'] as String? ?? 'Possible structure',
        sketchX: (json['sketchX'] as num?)?.toDouble() ?? 0.5,
        sketchY: (json['sketchY'] as num?)?.toDouble() ?? 0.5,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      );
}

class SatelliteStructureExtraction {
  SatelliteStructureExtraction({
    required this.potentialStructures,
    this.gpsBoundary = const [],
    this.roads = const [],
    this.waterBodies = const [],
  });

  final List<PotentialStructure> potentialStructures;
  final List<GpsPoint> gpsBoundary;
  final List<Map<String, dynamic>> roads;
  final List<Map<String, dynamic>> waterBodies;

  factory SatelliteStructureExtraction.fromJson(Map<String, dynamic> json) => SatelliteStructureExtraction(
        potentialStructures: (json['potentialStructures'] as List<dynamic>? ?? [])
            .map((e) => PotentialStructure.fromJson(e as Map<String, dynamic>))
            .toList(),
        gpsBoundary: (json['gpsBoundary'] as List<dynamic>? ?? [])
            .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        roads: (json['roads'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        waterBodies: (json['waterBodies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      );
}

class LayoutGeorefSession {
  LayoutGeorefSession({
    required this.id,
    required this.ebId,
    required this.status,
    this.alignmentMode = 'satellite_registration',
    this.layoutImageUrl,
    this.imageBounds,
    this.gpsBoundary = const [],
    this.potentialStructures = const [],
    this.controlPoints = const [],
    this.sketchBoundary = const [],
    this.alignmentScore,
    this.rmsErrorMeters,
    this.landmarks = const [],
  });

  final String id;
  final String ebId;
  final String status;
  final String alignmentMode;
  final String? layoutImageUrl;
  final ImageBounds? imageBounds;
  final List<GpsPoint> gpsBoundary;
  final List<PotentialStructure> potentialStructures;
  final List<GeorefControlPoint> controlPoints;
  final List<SketchPoint> sketchBoundary;
  final String? alignmentScore;
  final double? rmsErrorMeters;
  final List<dynamic> landmarks;

  factory LayoutGeorefSession.fromJson(Map<String, dynamic> json) => LayoutGeorefSession(
        id: json['id'] as String,
        ebId: json['ebId'] as String,
        status: json['status'] as String? ?? 'uploaded',
        alignmentMode: json['alignmentMode'] as String? ?? 'satellite_registration',
        layoutImageUrl: json['layoutImageUrl'] as String?,
        imageBounds: json['imageBounds'] != null
            ? ImageBounds.fromJson(Map<String, dynamic>.from(json['imageBounds'] as Map))
            : null,
        gpsBoundary: (json['gpsBoundary'] as List<dynamic>? ?? [])
            .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        potentialStructures: (json['potentialStructures'] as List<dynamic>? ?? [])
            .map((e) => PotentialStructure.fromJson(e as Map<String, dynamic>))
            .toList(),
        controlPoints: (json['controlPoints'] as List<dynamic>? ?? [])
            .map((e) => GeorefControlPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        sketchBoundary: (json['sketchBoundary'] as List<dynamic>? ?? [])
            .map((e) => SketchPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        alignmentScore: json['alignmentScore'] as String?,
        rmsErrorMeters: (json['rmsErrorMeters'] as num?)?.toDouble(),
        landmarks: json['landmarks'] as List<dynamic>? ?? [],
      );
}

class GeorefValidation {
  GeorefValidation({
    required this.polygonClosed,
    required this.areaAboveMinimum,
    required this.rmsErrorMeters,
    required this.alignmentScore,
    required this.controlPointCount,
    required this.potentialStructureCount,
    required this.warnings,
  });

  final bool polygonClosed;
  final bool areaAboveMinimum;
  final double rmsErrorMeters;
  final String alignmentScore;
  final int controlPointCount;
  final int potentialStructureCount;
  final List<String> warnings;

  String get alignmentLabel {
    switch (alignmentScore) {
      case 'excellent':
        return 'Excellent';
      case 'good':
        return 'Good';
      default:
        return 'Needs Review';
    }
  }

  factory GeorefValidation.fromJson(Map<String, dynamic> json) => GeorefValidation(
        polygonClosed: json['polygonClosed'] as bool? ?? false,
        areaAboveMinimum: json['areaAboveMinimum'] as bool? ?? false,
        rmsErrorMeters: (json['rmsErrorMeters'] as num?)?.toDouble() ?? 0,
        alignmentScore: json['alignmentScore'] as String? ?? 'needs_review',
        controlPointCount: json['controlPointCount'] as int? ?? 0,
        potentialStructureCount: json['potentialStructureCount'] as int? ?? 0,
        warnings: (json['warnings'] as List<dynamic>? ?? []).cast<String>(),
      );
}

enum MissionBoundarySource { officialGis, layoutMap, manualWalk }

class MissionIntelligencePackage {
  MissionIntelligencePackage({
    required this.generatedAt,
    required this.alignmentQualityPercent,
    required this.alignmentScore,
    required this.imageBounds,
    required this.gpsBoundary,
    required this.summary,
    this.raw,
  });

  final String generatedAt;
  final int alignmentQualityPercent;
  final String alignmentScore;
  final ImageBounds imageBounds;
  final List<GpsPoint> gpsBoundary;
  final MissionIntelligenceSummary summary;
  final Map<String, dynamic>? raw;

  factory MissionIntelligencePackage.fromJson(Map<String, dynamic> json) {
    final alignment = json['alignment'] as Map<String, dynamic>? ?? {};
    final boundary = json['boundary'] as Map<String, dynamic>? ?? {};
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    return MissionIntelligencePackage(
      generatedAt: json['generatedAt'] as String? ?? '',
      alignmentQualityPercent: alignment['qualityPercent'] as int? ?? 0,
      alignmentScore: alignment['score'] as String? ?? 'good',
      imageBounds: alignment['imageBounds'] != null
          ? ImageBounds.fromJson(Map<String, dynamic>.from(alignment['imageBounds'] as Map))
          : ImageBounds(north: 0, south: 0, east: 0, west: 0),
      gpsBoundary: (boundary['gpsRing'] as List<dynamic>? ?? [])
          .map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: MissionIntelligenceSummary(
        observationTargets: summary['observationTargets'] as int? ??
            summary['estimatedStructures'] as int? ?? 0,
        roadSegments: summary['roadSegments'] as int? ?? 0,
        possibleLandmarks: summary['possibleLandmarks'] as int? ?? 0,
        canalCrossings: summary['canalCrossings'] as int? ?? 0,
      ),
      raw: json,
    );
  }
}

class MissionIntelligenceSummary {
  const MissionIntelligenceSummary({
    required this.observationTargets,
    required this.roadSegments,
    required this.possibleLandmarks,
    required this.canalCrossings,
  });

  final int observationTargets;
  final int roadSegments;
  final int possibleLandmarks;
  final int canalCrossings;

  int get estimatedStructures => observationTargets;
}

