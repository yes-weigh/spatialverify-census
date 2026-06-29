import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'mission_service.dart';

/// Queues HLB discovery writes when offline; flushes when connectivity returns.
class MissionOfflineStore {
  MissionOfflineStore({MissionApiService? api}) : _api = api;

  MissionApiService? _api;
  static const _boxName = 'mission_offline_queue';
  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox(_boxName);
  }

  void attachApi(MissionApiService api) => _api = api;

  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  int get pendingCount => (_box?.length ?? 0);

  Future<void> enqueue(String ebId, String type, Map<String, dynamic> payload) async {
    await init();
    await _box!.add({
      'id': const Uuid().v4(),
      'ebId': ebId,
      'type': type,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> flush() async {
    if (_api == null) return 0;
    await init();
    if (!await isOnline) return 0;

    var synced = 0;
    final keys = _box!.keys.toList();
    for (final key in keys) {
      final item = Map<String, dynamic>.from(_box!.get(key) as Map);
      try {
        await _dispatch(item);
        await _box!.delete(key);
        synced++;
      } catch (_) {
        break;
      }
    }
    return synced;
  }

  Future<void> _dispatch(Map<String, dynamic> item) async {
    final api = _api!;
    final ebId = item['ebId'] as String;
    final type = item['type'] as String;
    final p = Map<String, dynamic>.from(item['payload'] as Map);

    switch (type) {
      case 'breadcrumb':
        await api.addBreadcrumb(
          ebId,
          (p['latitude'] as num).toDouble(),
          (p['longitude'] as num).toDouble(),
          accuracy: (p['accuracy'] as num?)?.toDouble(),
        );
      case 'building':
        await api.discoverBuilding(
          ebId,
          latitude: (p['latitude'] as num).toDouble(),
          longitude: (p['longitude'] as num).toDouble(),
          buildingType: p['buildingType'] as String,
          censusHouseCount: p['censusHouseCount'] as int?,
          buildingNumber: p['buildingNumber'] as int?,
        );
      case 'boundary':
        await api.addBoundaryVertex(
          ebId,
          (p['latitude'] as num).toDouble(),
          (p['longitude'] as num).toDouble(),
        );
      case 'landmark':
        await api.discoverLandmark(
          ebId,
          name: p['name'] as String,
          landmarkType: p['landmarkType'] as String,
          latitude: (p['latitude'] as num).toDouble(),
          longitude: (p['longitude'] as num).toDouble(),
        );
      case 'gap_resolve':
        await api.resolveCoverageGap(
          ebId,
          p['gapId'] as String,
          resolution: p['resolution'] as String,
          gapType: p['gapType'] as String,
          gapReason: p['gapReason'] as String,
          notes: p['notes'] as String?,
          latitude: (p['latitude'] as num?)?.toDouble(),
          longitude: (p['longitude'] as num?)?.toDouble(),
          resolvedLatitude: (p['resolvedLatitude'] as num?)?.toDouble(),
          resolvedLongitude: (p['resolvedLongitude'] as num?)?.toDouble(),
        );
      case 'finalize':
        await api.finalizeDraftMap(ebId);
    }
  }
}
