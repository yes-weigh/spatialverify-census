import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/mission_models.dart';
import 'firebase_mission_repository.dart';
import 'hlb_listing_computer.dart';
import 'hlb_local_cache.dart';
import 'hlb_local_state.dart';
import 'hlb_official_catalog.dart';
import 'hlb_state_computer.dart';

/// Local-first HLB work — device cache is source of truth; Firebase syncs when signed in.
class MissionLocalFirstService {
  MissionLocalFirstService({
    required HlbLocalCache cache,
    FirebaseMissionRepository? firebase,
  })  : _cache = cache,
        _firebase = firebase;

  final HlbLocalCache _cache;
  final FirebaseMissionRepository? _firebase;
  final _uuid = const Uuid();

  Future<HlbLocalState> _load(String ebId, {String? ebCode, String? projectId}) async {
    if (ebCode != null && projectId != null) {
      return _cache.getOrCreate(ebId: ebId, ebCode: ebCode, projectId: projectId);
    }
    final s = await _cache.get(ebId);
    if (s == null) throw StateError('HLB $ebId not initialized — call initEb first');
    return s;
  }

  Future<void> _save(HlbLocalState state) async {
    await _cache.put(state);
    if (_firebase != null && _firebase.isSignedIn) {
      try {
        await _firebase.pushEbState(state);
      } catch (_) {}
    }
  }

  Future<void> persistEbState(HlbLocalState state) => _save(state);

  static HlbLocalState mergePulledState(HlbLocalState local, HlbLocalState remote) {
    final remoteNewer = remote.updatedAt.isAfter(local.updatedAt);
    var merged = remoteNewer ? remote : local;
    final other = remoteNewer ? local : remote;

    final otherFinalized = other.layoutGeoref?['status'] == 'finalized';
    if (merged.officialBoundary == null &&
        other.officialBoundary != null &&
        (otherFinalized || other.officialBoundary!.source == 'layout_map')) {
      merged = merged.copyWith(
        officialBoundary: other.officialBoundary,
        missionIntelligence: other.missionIntelligence ?? merged.missionIntelligence,
        layoutGeoref: other.layoutGeoref ?? merged.layoutGeoref,
        blockStatus: other.blockStatus == 'published' ? other.blockStatus : merged.blockStatus,
      );
    } else if (otherFinalized && other.layoutGeoref != null) {
      merged = merged.copyWith(
        layoutGeoref: other.layoutGeoref,
        missionIntelligence: other.missionIntelligence ?? merged.missionIntelligence,
      );
    }

    return merged;
  }

  Future<void> initEb({
    required String ebId,
    required String ebCode,
    required String projectId,
  }) async {
    await _cache.getOrCreate(ebId: ebId, ebCode: ebCode, projectId: projectId);
    await syncInBackground(ebId);
  }

  Future<void> updateEbCode(String ebId, String ebCode) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _save(state.copyWith(ebCode: ebCode));
  }

  Future<void> syncInBackground(String ebId) async {
    if (_firebase == null || !_firebase.isSignedIn) return;
    try {
      final local = await _cache.get(ebId);
      if (local == null) return;
      final remote = await _firebase.pullEbState(local.projectId, ebId);
      if (remote == null) {
        await _firebase.pushEbState(local);
        await _cache.put(local.copyWith(serverSyncedAt: DateTime.now()));
        return;
      }
      if (remote.updatedAt.isAfter(local.updatedAt)) {
        final merged = mergePulledState(local, remote);
        await _cache.put(merged.copyWith(serverSyncedAt: DateTime.now()));
      } else {
        await _firebase.pushEbState(local);
        await _cache.put(local.copyWith(serverSyncedAt: DateTime.now()));
      }
    } catch (_) {}
  }

  Future<MissionDashboard> getDashboard(String ebId, {double? latitude, double? longitude}) async {
    final state = await _load(ebId);
    return HlbListingComputer.dashboard(state, lat: latitude, lng: longitude);
  }

  Future<DayReview> getDayReview(String ebId, {double? latitude, double? longitude}) async {
    final state = await _load(ebId);
    return HlbListingComputer.dayReview(state, lat: latitude, lng: longitude);
  }

  Future<List<MissionBuilding>> getRoute(String ebId) async {
    final state = await _load(ebId);
    return HlbListingComputer.route(state);
  }

  Future<Map<String, dynamic>> getCoverage(String ebId) async {
    final state = await _load(ebId);
    return HlbListingComputer.coverage(state);
  }

  Future<void> updateBuildingStatus(
    String ebId,
    String buildingId,
    MissionBuildingStatus status, {
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    var state = await _load(ebId);
    final statusStr = buildingStatusToApi(status);
    state = state.copyWith(
      buildings: [
        for (final b in state.buildings)
          if (b.localId == buildingId || b.serverId == buildingId)
            b.copyWith(
              status: statusStr,
              notes: notes ?? b.notes,
              latitude: latitude ?? b.latitude,
              longitude: longitude ?? b.longitude,
            )
          else
            b,
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<DiscoveryStatus> getDiscovery(String ebId, {double? latitude, double? longitude}) async {
    final state = await _load(ebId);
    return HlbStateComputer.discovery(state, enumLat: latitude, enumLng: longitude);
  }

  Future<CoverageGapsResponse> getCoverageGaps(String ebId, {double? latitude, double? longitude}) async {
    final state = await _load(ebId);
    return HlbStateComputer.coverageGaps(state, enumLat: latitude, enumLng: longitude);
  }

  Future<DraftHlbMap> getDraftMap(String ebId) async {
    final state = await _load(ebId);
    return HlbStateComputer.draftMap(state);
  }

  Future<ZeroExclusionValidation> validateDiscovery(String ebId) async {
    final state = await _load(ebId);
    return HlbStateComputer.validate(state);
  }

  Future<int> suggestBuildingNumber(String ebId, double lat, double lng) async {
    final state = await _load(ebId);
    return HlbStateComputer.suggestNumber(state, lat, lng);
  }

  Future<void> addBreadcrumb(String ebId, double lat, double lng, {double? accuracy}) async {
    var state = await _load(ebId);
    state = state.copyWith(
      breadcrumbs: [
        ...state.breadcrumbs,
        LocalBreadcrumb(localId: _uuid.v4(), latitude: lat, longitude: lng, accuracy: accuracy),
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> addBoundaryVertex(String ebId, double latitude, double longitude) async {
    var state = await _load(ebId);
    final seq = state.boundaryVertices.length;
    state = state.copyWith(
      boundaryVertices: [
        ...state.boundaryVertices,
        LocalBoundaryVertex(
          localId: _uuid.v4(),
          sequence: seq,
          latitude: latitude,
          longitude: longitude,
        ),
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> discoverBuilding(
    String ebId, {
    required double latitude,
    required double longitude,
    required String buildingType,
    int? censusHouseCount,
    int? buildingNumber,
  }) async {
    var state = await _load(ebId);
    final num = buildingNumber ?? HlbStateComputer.suggestNumber(state, latitude, longitude);
    final geoBounds = _geoBoundsFromState(state);
    final coords = _project(latitude, longitude, geoBounds);

    state = state.copyWith(
      buildings: [
        ...state.buildings,
        LocalBuilding(
          localId: _uuid.v4(),
          buildingNumber: num,
          censusHouseCount: censusHouseCount ?? 1,
          buildingType: buildingType,
          latitude: latitude,
          longitude: longitude,
          mapX: coords.x.clamp(0.05, 0.95),
          mapY: coords.y.clamp(0.05, 0.95),
        ),
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> discoverLandmark(
    String ebId, {
    required String name,
    required String landmarkType,
    required double latitude,
    required double longitude,
  }) async {
    final normalizedType = HlbOfficialCatalog.normalizeLandmarkType(landmarkType);
    var state = await _load(ebId);
    final geoBounds = _geoBoundsFromState(state);
    final coords = _project(latitude, longitude, geoBounds);
    state = state.copyWith(
      landmarks: [
        ...state.landmarks,
        LocalLandmark(
          localId: _uuid.v4(),
          name: name,
          landmarkType: normalizedType,
          latitude: latitude,
          longitude: longitude,
          mapX: coords.x,
          mapY: coords.y,
        ),
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> updateLandmarkPosition(
    String ebId, {
    required String localId,
    required double latitude,
    required double longitude,
  }) async {
    var state = await _load(ebId);
    final existing = state.landmarks.where((lm) => lm.localId == localId).firstOrNull;
    if (existing == null) return;

    final geoBounds = _geoBoundsFromState(state);
    final coords = _project(latitude, longitude, geoBounds);
    state = state.copyWith(
      landmarks: [
        for (final lm in state.landmarks)
          if (lm.localId == localId)
            LocalLandmark(
              localId: lm.localId,
              serverId: lm.serverId,
              name: lm.name,
              landmarkType: lm.landmarkType,
              latitude: latitude,
              longitude: longitude,
              mapX: coords.x.clamp(0.05, 0.95),
              mapY: coords.y.clamp(0.05, 0.95),
            )
          else
            lm,
      ],
    );
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> resolveCoverageGap(
    String ebId, {
    required String gapId,
    required String resolution,
    required String gapType,
    required String gapReason,
    String? notes,
    double? latitude,
    double? longitude,
    double? resolvedLatitude,
    double? resolvedLongitude,
  }) async {
    var state = await _load(ebId);
    final resolutions = state.gapResolutions.where((r) => r.gapFingerprint != gapId).toList();
    resolutions.add(LocalGapResolution(
      gapFingerprint: gapId,
      gapType: gapType,
      gapReason: gapReason,
      resolution: resolution,
      notes: notes,
      latitude: latitude,
      longitude: longitude,
    ));
    state = state.copyWith(gapResolutions: resolutions);
    await _save(state);
    syncInBackground(ebId);
  }

  Future<void> finalizeDraftMap(String ebId) async {
    var state = await _load(ebId);
    state = state.copyWith(phase: 'listing', blockStatus: 'published');
    await _save(state);
  }

  ({double minLat, double maxLat, double minLng, double maxLng}) _geoBoundsFromState(HlbLocalState state) {
    final points = <({double lat, double lng})>[];
    for (final v in state.boundaryVertices) {
      points.add((lat: v.latitude, lng: v.longitude));
    }
    for (final b in state.buildings) {
      points.add((lat: b.latitude, lng: b.longitude));
    }
    for (final c in state.breadcrumbs) {
      points.add((lat: c.latitude, lng: c.longitude));
    }
    if (points.isEmpty) return (minLat: 10.0, maxLat: 10.001, minLng: 76.0, maxLng: 76.001);
    return (
      minLat: points.map((p) => p.lat).reduce(math.min),
      maxLat: points.map((p) => p.lat).reduce(math.max),
      minLng: points.map((p) => p.lng).reduce(math.min),
      maxLng: points.map((p) => p.lng).reduce(math.max),
    );
  }

  ({double x, double y}) _project(double lat, double lng, ({double minLat, double maxLat, double minLng, double maxLng}) b) {
    final latSpan = math.max(b.maxLat - b.minLat, 0.0001);
    final lngSpan = math.max(b.maxLng - b.minLng, 0.0001);
    return (x: (lng - b.minLng) / lngSpan, y: (b.maxLat - lat) / latSpan);
  }

  Future<void> addSpatialObservation(
    String ebId, {
    required String type,
    required double latitude,
    required double longitude,
    double? heading,
    String? photoPath,
    String? linkedEntityId,
    String? label,
  }) async {
    var state = await _load(ebId);
    state = state.copyWith(
      spatialNodes: [
        ...state.spatialNodes,
        LocalSpatialNode(
          id: _uuid.v4(),
          type: type,
          latitude: latitude,
          longitude: longitude,
          heading: heading,
          photoPath: photoPath,
          linkedEntityId: linkedEntityId,
          label: label,
        ),
      ],
    );
    await _save(state);
  }

  Future<void> confirmRoadSegment(
    String ebId,
    List<({double lat, double lng})> points, {
    String segmentType = 'pucca_road',
    String? name,
  }) async {
    if (points.length < 2) return;
    var state = await _load(ebId);
    state = state.copyWith(
      roadSegments: [
        ...state.roadSegments,
        LocalRoadSegment(
          localId: _uuid.v4(),
          points: points,
          segmentType: HlbOfficialCatalog.normalizeLineType(segmentType),
          name: name,
        ),
      ],
    );
    await _save(state);
  }

  Future<void> deleteRoadSegment(String ebId, String localId) async {
    var state = await _load(ebId);
    final next = state.roadSegments.where((s) => s.localId != localId).toList();
    if (next.length == state.roadSegments.length) return;
    state = state.copyWith(roadSegments: next);
    await _save(state);
  }

  Future<void> addMapAnnotation(
    String ebId, {
    required String text,
    required String annotationType,
    required double latitude,
    required double longitude,
    double rotationDegrees = 0,
  }) async {
    var state = await _load(ebId);
    final geoBounds = _geoBoundsFromState(state);
    final coords = _project(latitude, longitude, geoBounds);
    state = state.copyWith(
      mapAnnotations: [
        ...state.mapAnnotations,
        LocalMapAnnotation(
          localId: _uuid.v4(),
          text: text,
          annotationType: annotationType,
          latitude: latitude,
          longitude: longitude,
          mapX: coords.x.clamp(0.02, 0.98),
          mapY: coords.y.clamp(0.02, 0.98),
          rotationDegrees: rotationDegrees,
        ),
      ],
    );
    await _save(state);
  }

  Future<void> saveLayoutMapFooter(
    String ebId, {
    String? enumeratorName,
    String? enumeratorDate,
    String? supervisorName,
    String? supervisorDate,
  }) async {
    var state = await _load(ebId);
    final footer = {
      if (enumeratorName != null) 'enumeratorName': enumeratorName,
      if (enumeratorDate != null) 'enumeratorDate': enumeratorDate,
      if (supervisorName != null) 'supervisorName': supervisorName,
      if (supervisorDate != null) 'supervisorDate': supervisorDate,
    };
    state = state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'layoutMapFooter': footer,
      },
    );
    await _save(state);
  }

  Future<void> savePdfMetadata(String ebId, Map<String, dynamic> metadata) async {
    var state = await _load(ebId);
    state = state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'pdfMetadata': metadata,
      },
    );
    await _save(state);
  }

  Future<HlbLocalState?> getRawState(String ebId) => _cache.get(ebId);

  Future<int> quickConfirmStructure(String ebId, {required double latitude, required double longitude}) async {
    final num = await suggestBuildingNumber(ebId, latitude, longitude);
    await discoverBuilding(
      ebId,
      latitude: latitude,
      longitude: longitude,
      buildingType: 'pucca_residential',
      buildingNumber: num,
      censusHouseCount: 1,
    );
    await addSpatialObservation(
      ebId,
      type: 'building',
      latitude: latitude,
      longitude: longitude,
      linkedEntityId: num.toString(),
      label: 'CN-${num.toString().padLeft(3, '0')}',
    );
    return num;
  }

  Future<void> recordIgnoredSuggestion(
    String ebId, {
    required String id,
    required String label,
    required double latitude,
    required double longitude,
  }) async {
    var state = await _load(ebId);
    final existing = state.ignoredSuggestions.where((s) => s.id == id).firstOrNull;
    final updated = state.ignoredSuggestions.where((s) => s.id != id).toList();
    updated.add(LocalIgnoredSuggestion(
      id: id,
      label: label,
      latitude: latitude,
      longitude: longitude,
      timesIgnored: (existing?.timesIgnored ?? 0) + 1,
    ));
    state = state.copyWith(ignoredSuggestions: updated);
    await _save(state);
  }

  Future<void> dismissIgnoredSuggestion(String ebId, String id) async {
    var state = await _load(ebId);
    state = state.copyWith(
      ignoredSuggestions: state.ignoredSuggestions.where((s) => s.id != id).toList(),
    );
    await _save(state);
  }

  bool isInsideOfficialBoundary(HlbLocalState state, double lat, double lng) =>
      HlbStateComputer.isInsideOfficialBoundary(state, lat, lng);

  Future<void> recordBoundaryAudit(String ebId, String event) async {
    var state = await _load(ebId);
    final audit = state.boundaryAudit ?? LocalBoundaryAudit();
    final now = DateTime.now();
    LocalBoundaryAudit updated;
    switch (event) {
      case 'entered':
        updated = audit.copyWith(enteredBoundaryAt: now);
      case 'left':
        updated = audit.copyWith(leftBoundaryAt: now);
      case 'start_reached':
        updated = audit.copyWith(startPointReachedAt: now);
      case 'discovery_started':
        updated = audit.copyWith(discoveryStartedAt: now);
      default:
        return;
    }
    state = state.copyWith(boundaryAudit: updated);
    await _save(state);
  }

  Future<void> recordOutsideBoundaryDiscovery(
    String ebId, {
    required double latitude,
    required double longitude,
    required String label,
    required bool overridden,
  }) async {
    var state = await _load(ebId);
    final audit = state.boundaryAudit ?? LocalBoundaryAudit();
    final discovery = LocalOutsideDiscovery(
      latitude: latitude,
      longitude: longitude,
      label: label,
      overridden: overridden,
    );
    state = state.copyWith(
      boundaryAudit: audit.copyWith(
        outsideBoundaryDiscoveries: [...audit.outsideBoundaryDiscoveries, discovery],
      ),
    );
    await _save(state);
  }

  Future<void> saveMissionIntelligence(String ebId, Map<String, dynamic> intelligence) async {
    final state = await _load(ebId);
    await _save(state.copyWith(
      missionIntelligence: intelligence,
      layoutGeoref: {
        ...?state.layoutGeoref,
        'missionIntelligence': intelligence,
        'potentialStructures': (intelligence['hypotheses'] as Map?)?['observationTargets'] ??
            (intelligence['hypotheses'] as Map?)?['structures'] ??
            [],
        'digitalTwin': intelligence['digitalTwin'],
      },
    ));
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
