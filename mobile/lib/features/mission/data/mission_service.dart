import '../../../core/network/api_client.dart';
import '../models/mission_models.dart';

class MissionApiService {
  MissionApiService({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Future<List<EnumerationBlock>> listEbs(String projectId) async {
    final res = await _api.get('/mission/projects/$projectId/ebs');
    final list = res.data as List<dynamic>;
    return list.map((e) => EnumerationBlock.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<EnumerationBlock> createEb(String projectId, {required String ebCode, String? name}) async {
    final res = await _api.post('/mission/projects/$projectId/ebs', data: {
      'ebCode': ebCode,
      if (name != null) 'name': name,
    });
    return EnumerationBlock.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String?> uploadLayout(String ebId, String filePath) async {
    final res = await _api.uploadFile('/mission/ebs/$ebId/layout-upload', filePath);
    final data = res.data as Map<String, dynamic>;
    return data['layoutImageUrl'] as String?;
  }

  Future<MissionPlan> getPlan(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId');
    return MissionPlan.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MissionPlan> savePlan(String ebId, MissionPlanDraft draft) async {
    final res = await _api.put('/mission/ebs/$ebId/plan', data: draft.toJson());
    return MissionPlan.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> publishEb(String ebId) async {
    await _api.post('/mission/ebs/$ebId/start');
  }

  Future<void> startMission(String ebId) => publishEb(ebId);

  Future<MissionDashboard> getDashboard(String ebId, {double? latitude, double? longitude}) async {
    final res = await _api.get('/mission/ebs/$ebId/dashboard', queryParameters: {
      if (latitude != null) 'lat': latitude,
      if (longitude != null) 'lng': longitude,
    });
    return MissionDashboard.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DayReview> getDayReview(String ebId, {double? latitude, double? longitude}) async {
    final res = await _api.get('/mission/ebs/$ebId/day-review', queryParameters: {
      if (latitude != null) 'lat': latitude,
      if (longitude != null) 'lng': longitude,
    });
    return DayReview.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<MissionBuilding>> getRoute(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/route');
    final data = res.data as Map<String, dynamic>;
    return (data['buildings'] as List<dynamic>)
        .map((e) => MissionBuilding.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateBuildingStatus(
    String buildingId,
    MissionBuildingStatus status, {
    String? notes,
    String? assetId,
    double? latitude,
    double? longitude,
  }) async {
    await _api.patch('/mission/buildings/$buildingId/status', data: {
      'status': buildingStatusToApi(status),
      if (notes != null) 'notes': notes,
      if (assetId != null) 'assetId': assetId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  Future<void> addBreadcrumb(String ebId, double lat, double lng, {double? accuracy}) async {
    await _api.post('/mission/ebs/$ebId/breadcrumbs', data: {
      'latitude': lat,
      'longitude': lng,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  Future<Map<String, dynamic>> getCoverage(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/coverage');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOfflineSnapshot(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/offline-snapshot');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getHlbBoundaryMissionByEb(String ebId) async {
    final res = await _api.get('/hlb-boundaries/by-eb/$ebId/mission');
    return res.data as Map<String, dynamic>;
  }

  Future<void> postBoundaryAudit(String ebId, String event) async {
    await _api.post('/hlb-boundaries/eb/$ebId/audit', data: {'event': event});
  }

  Future<void> postOutsideDiscovery(
    String ebId, {
    required double latitude,
    required double longitude,
    required String label,
    required bool overridden,
  }) async {
    await _api.post('/hlb-boundaries/eb/$ebId/outside-discovery', data: {
      'latitude': latitude,
      'longitude': longitude,
      'label': label,
      'overridden': overridden,
    });
  }

  Future<CoverageGapsResponse> getCoverageGaps(String ebId, {double? latitude, double? longitude}) async {
    final res = await _api.get('/mission/ebs/$ebId/gaps', queryParameters: {
      if (latitude != null) 'lat': latitude,
      if (longitude != null) 'lng': longitude,
    });
    return CoverageGapsResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> resolveCoverageGap(
    String ebId,
    String gapId, {
    required String resolution,
    required String gapType,
    required String gapReason,
    String? notes,
    double? latitude,
    double? longitude,
    double? resolvedLatitude,
    double? resolvedLongitude,
  }) async {
    await _api.post('/mission/ebs/$ebId/gaps/${Uri.encodeComponent(gapId)}/resolve', data: {
      'resolution': resolution,
      'gapType': gapType,
      'gapReason': gapReason,
      if (notes != null) 'notes': notes,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (resolvedLatitude != null) 'resolvedLatitude': resolvedLatitude,
      if (resolvedLongitude != null) 'resolvedLongitude': resolvedLongitude,
    });
  }

  Future<DiscoveryStatus> getDiscovery(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/discovery');
    return DiscoveryStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DraftHlbMap> getDraftMap(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/draft-map');
    return DraftHlbMap.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ZeroExclusionValidation> validateDiscovery(String ebId) async {
    final res = await _api.get('/mission/ebs/$ebId/validate');
    return ZeroExclusionValidation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> suggestBuildingLabel(String ebId, double lat, double lng) async {
    final res = await _api.get('/mission/ebs/$ebId/suggest-number', queryParameters: {
      'lat': lat,
      'lng': lng,
    });
    final data = res.data as Map<String, dynamic>;
    return data['label'] as String;
  }

  Future<int> suggestBuildingNumber(String ebId, double lat, double lng) async {
    final res = await _api.get('/mission/ebs/$ebId/suggest-number', queryParameters: {
      'lat': lat,
      'lng': lng,
    });
    final data = res.data as Map<String, dynamic>;
    return data['buildingNumber'] as int;
  }

  Future<void> discoverBuilding(
    String ebId, {
    required double latitude,
    required double longitude,
    required String buildingType,
    int? censusHouseCount,
    int? buildingNumber,
  }) async {
    await _api.post('/mission/ebs/$ebId/buildings/discover', data: {
      'latitude': latitude,
      'longitude': longitude,
      'buildingType': buildingType,
      if (censusHouseCount != null) 'censusHouseCount': censusHouseCount,
      if (buildingNumber != null) 'buildingNumber': buildingNumber,
    });
  }

  Future<void> addBoundaryVertex(String ebId, double latitude, double longitude) async {
    await _api.post('/mission/ebs/$ebId/boundary-vertices', data: {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> discoverLandmark(
    String ebId, {
    required String name,
    required String landmarkType,
    required double latitude,
    required double longitude,
  }) async {
    await _api.post('/mission/ebs/$ebId/landmarks/discover', data: {
      'name': name,
      'landmarkType': landmarkType,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> finalizeDraftMap(String ebId) async {
    await _api.post('/mission/ebs/$ebId/finalize-draft');
  }
}

class MissionPlan {
  MissionPlan({
    required this.boundaryMap,
    required this.buildings,
    required this.landmarks,
    this.layoutImageUrl,
    this.northBearing = 0,
    this.routeBuildingIds = const [],
  });

  final List<MapPoint> boundaryMap;
  final List<MissionBuilding> buildings;
  final List<MissionLandmark> landmarks;
  final String? layoutImageUrl;
  final double northBearing;
  final List<String> routeBuildingIds;

  factory MissionPlan.fromJson(Map<String, dynamic> json) {
    final block = json['block'] as Map<String, dynamic>;
    final boundary = (block['boundary_map'] as List<dynamic>? ?? [])
        .map((e) => MapPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return MissionPlan(
      boundaryMap: boundary,
      buildings: (json['buildings'] as List<dynamic>? ?? [])
          .map((e) => MissionBuilding.fromJson(e as Map<String, dynamic>))
          .toList(),
      landmarks: (json['landmarks'] as List<dynamic>? ?? [])
          .map((e) => MissionLandmark(
                name: e['name'] as String,
                landmarkType: e['landmark_type'] as String,
                mapX: (e['map_x'] as num).toDouble(),
                mapY: (e['map_y'] as num).toDouble(),
              ))
          .toList(),
      layoutImageUrl: json['layoutImageUrl'] as String?,
      northBearing: (block['north_bearing'] as num?)?.toDouble() ?? 0,
      routeBuildingIds: (block['route_building_ids'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

class MissionPlanDraft {
  MissionPlanDraft({
    required this.boundaryMap,
    required this.buildings,
    required this.landmarks,
    this.northBearing = 0,
    this.routeBuildingIds = const [],
  });

  final List<MapPoint> boundaryMap;
  final List<MissionBuilding> buildings;
  final List<MissionLandmark> landmarks;
  final double northBearing;
  final List<String> routeBuildingIds;

  Map<String, dynamic> toJson() => {
        'boundaryMap': boundaryMap.map((p) => p.toJson()).toList(),
        'northBearing': northBearing,
        'routeBuildingIds': routeBuildingIds,
        'buildings': buildings.map((b) => b.toPlanJson()).toList(),
        'landmarks': landmarks.map((l) => l.toPlanJson()).toList(),
      };
}
