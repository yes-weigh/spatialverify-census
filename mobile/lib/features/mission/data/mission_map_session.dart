import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/storage/mission_layout_storage.dart';
import '../../../core/utils/json_map_utils.dart';
import '../models/layout_georef_models.dart';
import 'hlb_geo_engine.dart';
import '../data/mission_local_first_service.dart';

/// Pin for discovered buildings on the live mission map.
class MissionDraftPin {
  const MissionDraftPin({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String label;
}

/// Building with census symbol metadata for the HLB top layer.
class MissionHlbBuildingPin {
  const MissionHlbBuildingPin({
    required this.id,
    required this.buildingNumber,
    required this.censusHouseCount,
    required this.buildingType,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final int buildingNumber;
  final int censusHouseCount;
  final String buildingType;
  final double latitude;
  final double longitude;

  String get label => 'CN-${buildingNumber.toString().padLeft(3, '0')}';
}

/// Landmark for the HLB top layer.
class MissionHlbLandmarkPin {
  const MissionHlbLandmarkPin({
    required this.id,
    required this.name,
    required this.landmarkType,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String landmarkType;
  final double latitude;
  final double longitude;
}

/// Line feature (road, canal, river, etc.) on the live mission map.
class MissionMapLineFeature {
  const MissionMapLineFeature({
    required this.id,
    required this.segmentType,
    required this.points,
    this.name,
  });

  final String id;
  final String segmentType;
  final String? name;
  final List<GpsPoint> points;
}

List<({double x, double y})> parseUvRingFromJson(dynamic raw) {
  if (raw is! List) return [];
  return [
    for (final p in raw)
      if (p is Map)
        (
          x: ((p['x'] ?? p['u']) as num).toDouble(),
          y: ((p['y'] ?? p['v']) as num).toDouble(),
        ),
  ];
}

/// Everything needed to render the gamified mission map for one HLB.
class MissionMapSession {
  const MissionMapSession({
    required this.boundaryRing,
    required this.mapCenter,
    this.layoutImagePath,
    this.imageBounds,
    this.uvRing = const [],
    this.startPoint,
    this.draftPins = const [],
    this.hlbBuildings = const [],
    this.hlbLandmarks = const [],
    this.hlbLineFeatures = const [],
    this.walkPath = const [],
    this.boundarySource,
  });

  final List<GpsPoint> boundaryRing;
  final LatLng mapCenter;
  final String? layoutImagePath;
  final ImageBounds? imageBounds;
  final List<({double x, double y})> uvRing;
  final gmaps.LatLng? startPoint;
  final List<MissionDraftPin> draftPins;
  final List<MissionHlbBuildingPin> hlbBuildings;
  final List<MissionHlbLandmarkPin> hlbLandmarks;
  final List<MissionMapLineFeature> hlbLineFeatures;
  final List<GpsPoint> walkPath;
  final String? boundarySource;

  bool get hasBoundary => boundaryRing.length >= 3;
}

/// Nearest HLB landmark to a map long-press (for fine-tune entry).
MissionHlbLandmarkPin? nearestHlbLandmark(
  List<MissionHlbLandmarkPin> landmarks,
  double latitude,
  double longitude, {
  double maxMeters = 28,
}) {
  MissionHlbLandmarkPin? hit;
  var best = maxMeters;
  for (final lm in landmarks) {
    final d = HlbGeoEngine.haversineMeters(latitude, longitude, lm.latitude, lm.longitude);
    if (d <= best) {
      best = d;
      hit = lm;
    }
  }
  return hit;
}

Future<MissionMapSession?> loadMissionMapSession(
  MissionLocalFirstService local,
  String ebId,
) async {
  final state = await local.getRawState(ebId);
  if (state == null) return null;

  final official = state.officialBoundary;
  List<GpsPoint> ring = [];
  gmaps.LatLng? start;

  if (official != null) {
    ring = official.ringLatLng.map((p) => GpsPoint(p.lat, p.lng)).toList();
    start = gmaps.LatLng(official.startLat, official.startLng);
  } else {
    final georefBoundary = state.layoutGeoref?['gpsBoundary'] as List<dynamic>?;
    if (georefBoundary != null) {
      ring = georefBoundary
          .map((e) => GpsPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  }

  LatLng center;
  if (ring.isNotEmpty) {
    var lat = 0.0;
    var lng = 0.0;
    for (final p in ring) {
      lat += p.lat;
      lng += p.lng;
    }
    center = LatLng(lat / ring.length, lng / ring.length);
  } else if (state.breadcrumbs.isNotEmpty) {
    final b = state.breadcrumbs.last;
    center = LatLng(b.latitude, b.longitude);
  } else {
    center = const LatLng(20.5937, 78.9629);
  }

  String? layoutPath;
  ImageBounds? imageBounds;
  List<({double x, double y})> uvRing = [];

  final intelRaw = state.missionIntelligence ?? state.layoutGeoref?['missionIntelligence'];
  if (intelRaw is Map) {
    final intelMap = deepJsonMap(intelRaw);
    layoutPath = intelMap['layoutImagePath'] as String?;
    final alignment = intelMap['alignment'] as Map<String, dynamic>?;
    if (alignment?['imageBounds'] != null) {
      imageBounds = ImageBounds.fromJson(Map<String, dynamic>.from(alignment!['imageBounds'] as Map));
    }
    final boundary = intelMap['boundary'] as Map<String, dynamic>?;
    uvRing = parseUvRingFromJson(boundary?['uvRing']);
  }

  if (layoutPath == null || !await missionLayoutExists(layoutPath)) {
    layoutPath = await defaultMissionLayoutRef(ebId);
  }
  if (layoutPath != null && !await missionLayoutExists(layoutPath)) {
    layoutPath = null;
  }

  if (imageBounds == null && state.layoutGeoref?['imageBounds'] != null) {
    imageBounds = ImageBounds.fromJson(
      Map<String, dynamic>.from(state.layoutGeoref!['imageBounds'] as Map),
    );
  }
  if (uvRing.isEmpty) {
    uvRing = parseUvRingFromJson(state.layoutGeoref?['uvRing']);
  }

  final draftPins = state.buildings
      .map(
        (b) => MissionDraftPin(
          id: b.localId,
          latitude: b.latitude,
          longitude: b.longitude,
          label: 'CN-${b.buildingNumber.toString().padLeft(3, '0')}',
        ),
      )
      .toList();

  final hlbBuildings = state.buildings
      .map(
        (b) => MissionHlbBuildingPin(
          id: b.localId,
          buildingNumber: b.buildingNumber,
          censusHouseCount: b.censusHouseCount,
          buildingType: b.buildingType,
          latitude: b.latitude,
          longitude: b.longitude,
        ),
      )
      .toList();

  final hlbLandmarks = state.landmarks
      .map(
        (lm) => MissionHlbLandmarkPin(
          id: lm.localId,
          name: lm.name,
          landmarkType: lm.landmarkType,
          latitude: lm.latitude,
          longitude: lm.longitude,
        ),
      )
      .toList();

  final hlbLineFeatures = state.roadSegments
      .map(
        (seg) => MissionMapLineFeature(
          id: seg.localId,
          segmentType: seg.segmentType,
          name: seg.name,
          points: seg.points.map((p) => GpsPoint(p.lat, p.lng)).toList(),
        ),
      )
      .toList();

  final walkPath = state.breadcrumbs
      .map((b) => GpsPoint(b.latitude, b.longitude))
      .toList();

  return MissionMapSession(
    boundaryRing: ring,
    mapCenter: center,
    layoutImagePath: layoutPath,
    imageBounds: imageBounds,
    uvRing: uvRing,
    startPoint: start,
    draftPins: draftPins,
    hlbBuildings: hlbBuildings,
    hlbLandmarks: hlbLandmarks,
    hlbLineFeatures: hlbLineFeatures,
    walkPath: walkPath,
    boundarySource: official?.source ?? state.layoutGeoref?['source'] as String?,
  );
}
