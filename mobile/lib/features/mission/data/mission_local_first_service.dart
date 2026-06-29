import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../models/mission_models.dart';
import 'firebase_mission_repository.dart';
import 'hlb_local_cache.dart';
import 'hlb_local_state.dart';
import 'hlb_official_catalog.dart';
import 'hlb_state_computer.dart';
import 'mission_offline_store.dart';
import 'mission_service.dart';

/// Local-first HLB discovery — reads/writes device cache; syncs silently when online.
class MissionLocalFirstService {
  MissionLocalFirstService({
    required MissionApiService api,
    required HlbLocalCache cache,
    required MissionOfflineStore syncQueue,
    FirebaseMissionRepository? firebase,
  })  : _api = api,
        _cache = cache,
        _sync = syncQueue,
        _firebase = firebase;

  final MissionApiService _api;
  final HlbLocalCache _cache;
  final MissionOfflineStore _sync;
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
    if (AppConfig.useFirebase && _firebase != null && _firebase.isSignedIn) {
      try {
        await _firebase.pushEbState(state);
      } catch (_) {}
    }
  }

  /// Persist local HLB state and push to cloud when signed in.
  Future<void> persistEbState(HlbLocalState state) async {
    await _save(state);
  }

  /// Keep finalized on-device layout boundaries when cloud copy is stale.
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

  /// Call when entering an HLB mission. Hydrates from server silently when online.
  Future<void> initEb({
    required String ebId,
    required String ebCode,
    required String projectId,
  }) async {
    await _cache.getOrCreate(ebId: ebId, ebCode: ebCode, projectId: projectId);
    if (AppConfig.useFirebase && _firebase != null) {
      await syncInBackground(ebId);
      return;
    }
    if (AppConfig.standaloneMode) return;
    await syncInBackground(ebId);
    await hydrateOfficialBoundary(ebId);
  }

  Future<void> updateEbCode(String ebId, String ebCode) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _save(state.copyWith(ebCode: ebCode));
  }

  /// Pull server state and flush pending writes — never blocks UI.
  Future<void> syncInBackground(String ebId) async {
    if (AppConfig.useFirebase) {
      if (_firebase != null && _firebase.isSignedIn) {
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
      return;
    }
    if (AppConfig.standaloneMode) return;
    _sync.attachApi(_api);
    try {
      if (await _sync.isOnline) {
        await _sync.flush();
        final res = await _api.getOfflineSnapshot(ebId);
        final snapshot = HlbLocalState.fromServerSnapshot(res);
        await _save(snapshot);
      }
    } catch (_) {}
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
    await _sync.enqueue(ebId, 'breadcrumb', {
      'latitude': lat,
      'longitude': lng,
      if (accuracy != null) 'accuracy': accuracy,
    });
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
    await _sync.enqueue(ebId, 'boundary', {'latitude': latitude, 'longitude': longitude});
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
    await _sync.enqueue(ebId, 'building', {
      'latitude': latitude,
      'longitude': longitude,
      'buildingType': buildingType,
      'censusHouseCount': censusHouseCount ?? 1,
      'buildingNumber': num,
    });
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
    await _sync.enqueue(ebId, 'landmark', {
      'name': name,
      'landmarkType': normalizedType,
      'latitude': latitude,
      'longitude': longitude,
    });
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
    await _sync.enqueue(ebId, 'landmark', {
      'name': existing.name,
      'landmarkType': existing.landmarkType,
      'latitude': latitude,
      'longitude': longitude,
    });
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
    await _sync.enqueue(ebId, 'gap_resolve', {
      'gapId': gapId,
      'resolution': resolution,
      'gapType': gapType,
      'gapReason': gapReason,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'resolvedLatitude': resolvedLatitude,
      'resolvedLongitude': resolvedLongitude,
    });
    syncInBackground(ebId);
  }

  Future<void> finalizeDraftMap(String ebId) async {
    var state = await _load(ebId);
    state = state.copyWith(phase: 'listing', blockStatus: 'published');
    await _save(state);
    try {
      if (await _sync.isOnline) await _api.finalizeDraftMap(ebId);
    } catch (_) {
      await _sync.enqueue(ebId, 'finalize', {});
    }
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

  /// Quick confirm — default □ Pucca Residential, 1 census house.
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
    try {
      if (await _sync.isOnline) await _api.postBoundaryAudit(ebId, event);
    } catch (_) {}
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
    try {
      if (await _sync.isOnline) {
        await _api.postOutsideDiscovery(
          ebId,
          latitude: latitude,
          longitude: longitude,
          label: label,
          overridden: overridden,
        );
      }
    } catch (_) {}
  }

  Future<void> hydrateOfficialBoundary(String ebId) async {
    if (AppConfig.standaloneMode) return;
    try {
      if (!await _sync.isOnline) return;
      final pkg = await _api.getHlbBoundaryMissionByEb(ebId);
      var state = await _load(ebId);
      final boundaryJson = pkg['boundary'] as Map<String, dynamic>?;
      if (boundaryJson == null) return;
      state = state.copyWith(
        officialBoundary: LocalOfficialBoundary.fromServer(boundaryJson),
        boundaryAudit: pkg['audit'] != null
            ? LocalBoundaryAudit.fromJson(Map<String, dynamic>.from(pkg['audit'] as Map))
            : state.boundaryAudit,
      );
      await _save(state);
    } catch (_) {}
  }

  /// Persist mission intelligence hypotheses for offline discovery.
  Future<void> saveMissionIntelligence(String ebId, Map<String, dynamic> intelligence) async {
    try {
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
    } catch (_) {}
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
