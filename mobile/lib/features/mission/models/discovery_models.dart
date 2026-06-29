import '../../../core/models/models.dart';
import '../../scanner/data/object_detector.dart';

enum DiscoveryObjectType { building, road, landmark }

enum DiscoveryCandidateStatus { suggested, confirmed, rejected }

/// AI-suggested object awaiting enumerator confirmation — never auto-created.
class DiscoveryCandidate {
  DiscoveryCandidate({
    required this.id,
    required this.type,
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.status = DiscoveryCandidateStatus.suggested,
    this.latitude,
    this.longitude,
    this.heading,
    this.detectedAt,
    this.source = 'camera',
    this.hypothesisId,
    this.distanceMeters,
  });

  final String id;
  final DiscoveryObjectType type;
  final String label;
  final double confidence;
  final BoundingBox boundingBox;
  final DiscoveryCandidateStatus status;
  final double? latitude;
  final double? longitude;
  final double? heading;
  final DateTime? detectedAt;
  final String source;
  final String? hypothesisId;
  final double? distanceMeters;

  String get typeLabel {
    switch (type) {
      case DiscoveryObjectType.building:
        return source == 'satellite' ? 'Observation Target' : 'Possible Structure';
      case DiscoveryObjectType.landmark:
        return 'Possible Landmark';
      case DiscoveryObjectType.road:
        return 'Road';
    }
  }

  /// Camera overlay only — structures and landmarks, never roads.
  bool get showOnCamera => type != DiscoveryObjectType.road && status != DiscoveryCandidateStatus.rejected;

  DiscoveryCandidate copyWith({
    DiscoveryCandidateStatus? status,
    double? latitude,
    double? longitude,
    double? heading,
  }) {
    return DiscoveryCandidate(
      id: id,
      type: type,
      label: label,
      confidence: confidence,
      boundingBox: boundingBox,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      detectedAt: detectedAt,
      source: source,
      hypothesisId: hypothesisId,
      distanceMeters: distanceMeters,
    );
  }

  factory DiscoveryCandidate.fromSatelliteHypothesis({
    required String id,
    required String hypothesisId,
    required String label,
    required double confidence,
    required double latitude,
    required double longitude,
    double? distanceMeters,
  }) {
    return DiscoveryCandidate(
      id: id,
      type: DiscoveryObjectType.building,
      label: label,
      confidence: confidence,
      boundingBox: const BoundingBox(x: 0.38, y: 0.32, width: 0.24, height: 0.28),
      latitude: latitude,
      longitude: longitude,
      detectedAt: DateTime.now(),
      source: 'satellite',
      hypothesisId: hypothesisId,
      distanceMeters: distanceMeters,
    );
  }

  factory DiscoveryCandidate.fromDetection(
    DetectedObject d, {
    required String id,
    double? latitude,
    double? longitude,
    double? heading,
  }) {
    final type = DiscoveryClassifier.classifyForCamera(d);
    return DiscoveryCandidate(
      id: id,
      type: type,
      label: d.label,
      confidence: d.confidence,
      boundingBox: d.boundingBox,
      latitude: latitude,
      longitude: longitude,
      heading: heading,
      detectedAt: DateTime.now(),
    );
  }
}

class DiscoveryClassifier {
  static const _landmarkKeywords = [
    'sign', 'hydrant', 'pole', 'manhole', 'transformer', 'mosque', 'temple', 'church',
  ];

  static DiscoveryObjectType classifyForCamera(DetectedObject d) {
    final l = d.label.toLowerCase();
    if (_landmarkKeywords.any(l.contains)) return DiscoveryObjectType.landmark;
    return DiscoveryObjectType.building;
  }

  /// Legacy — roads inferred from walk path only, not camera boxes.
  static DiscoveryObjectType classify(DetectedObject d) => classifyForCamera(d);
}

/// Lightweight spatial graph node — not photogrammetry.
class SpatialGraphNode {
  SpatialGraphNode({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.photoPath,
    this.linkedEntityId,
    this.label,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final String type;
  final double latitude;
  final double longitude;
  final double? heading;
  final String? photoPath;
  final String? linkedEntityId;
  final String? label;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'heading': heading,
        'photoPath': photoPath,
        'linkedEntityId': linkedEntityId,
        'label': label,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SpatialGraphNode.fromJson(Map<String, dynamic> json) => SpatialGraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        photoPath: json['photoPath'] as String?,
        linkedEntityId: json['linkedEntityId'] as String?,
        label: json['label'] as String?,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      );
}

class LocalRoadSegment {
  LocalRoadSegment({
    required this.localId,
    required this.points,
    this.confirmed = true,
  });

  final String localId;
  final List<({double lat, double lng})> points;
  final bool confirmed;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'points': points.map((p) => {'lat': p.lat, 'lng': p.lng}).toList(),
        'confirmed': confirmed,
      };

  factory LocalRoadSegment.fromJson(Map<String, dynamic> json) => LocalRoadSegment(
        localId: json['localId'] as String,
        points: (json['points'] as List<dynamic>)
            .map((p) => (lat: (p['lat'] as num).toDouble(), lng: (p['lng'] as num).toDouble()))
            .toList(),
        confirmed: json['confirmed'] as bool? ?? true,
      );
}
