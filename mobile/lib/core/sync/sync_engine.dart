import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/models/models.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/config/app_config.dart';

class SyncEngine {
  SyncEngine({
    required ApiClient apiClient,
    required AppDatabase database,
    required SecureLocalStorage storage,
  })  : _api = apiClient,
        _db = database,
        _storage = storage;

  final ApiClient _api;
  final AppDatabase _db;
  final SecureLocalStorage _storage;
  final _uuid = const Uuid();

  bool _isSyncing = false;

  Future<SyncResult> sync(String projectId) async {
    if (_isSyncing) return SyncResult(skipped: true);
    _isSyncing = true;

    try {
      final pushResult = await _pushPendingChanges();
      final pullResult = await _pullRemoteChanges(projectId);
      await _storage.setLastSyncAt(DateTime.now());

      return SyncResult(
        pushed: pushResult.synced.length,
        pulled: pullResult.assetCount,
        conflicts: pushResult.conflicts.length,
        failed: pushResult.failed.length,
      );
    } finally {
      _isSyncing = false;
    }
  }

  Future<PushResult> _pushPendingChanges() async {
    final items = await _db.getPendingSyncItems();
    if (items.isEmpty) {
      return PushResult(synced: [], conflicts: [], failed: []);
    }

    final deviceId = _storage.deviceId ?? _uuid.v4();
    final batch = items.take(AppConfig.syncBatchSize).map((item) => {
          'entity_type': item.entityType,
          'entity_id': item.entityId,
          'client_id': item.clientId,
          'operation': item.operation,
          'payload': jsonDecode(item.payloadJson),
          'timestamp': item.createdAt.toIso8601String(),
        }).toList();

    try {
      final response = await _api.post('/survey/sync/push', data: {
        'deviceId': deviceId,
        'items': batch,
      });

      final data = response.data as Map<String, dynamic>;
      final synced = (data['synced'] as List<dynamic>).cast<String>();
      final conflicts = (data['conflicts'] as List<dynamic>).cast<String>();
      final failed = (data['failed'] as List<dynamic>).cast<String>();

      for (final item in items) {
        if (synced.contains(item.clientId)) {
          await _db.updateSyncStatus(item.id, 'synced');
        } else if (conflicts.contains(item.clientId)) {
          await _db.updateSyncStatus(item.id, 'conflict');
        } else if (failed.contains(item.clientId)) {
          await _db.updateSyncStatus(
            item.id,
            'failed',
            error: 'Server rejected',
          );
        }
      }

      return PushResult(synced: synced, conflicts: conflicts, failed: failed);
    } catch (e) {
      for (final item in items) {
        if (item.retryCount < AppConfig.syncRetryMax) {
          await (_db.update(_db.syncQueueItems)..where((s) => s.id.equals(item.id)))
              .write(SyncQueueItemsCompanion(
            retryCount: Value(item.retryCount + 1),
            status: const Value('pending'),
          ));
        } else {
          await _db.updateSyncStatus(item.id, 'failed', error: e.toString());
        }
      }
      return PushResult(synced: [], conflicts: [], failed: items.map((i) => i.clientId).toList());
    }
  }

  Future<PullResult> _pullRemoteChanges(String projectId) async {
    final since = _storage.lastSyncAt?.toIso8601String();
    try {
      final response = await _api.get(
        '/survey/sync/pull/$projectId',
        queryParameters: since != null ? {'since': since} : null,
      );

      final data = response.data as Map<String, dynamic>;
      final assets = (data['assets'] as List<dynamic>?) ?? [];

      for (final assetData in assets) {
        final asset = Asset.fromJson(assetData as Map<String, dynamic>);
        await _db.into(_db.localAssets).insertOnConflictUpdate(
              LocalAssetsCompanion.insert(
                id: asset.id,
                projectId: asset.projectId,
                categoryId: Value(asset.categoryId),
                name: asset.name,
                status: asset.statusString,
                latitude: asset.latitude,
                longitude: asset.longitude,
                altitude: Value(asset.altitude),
                heading: Value(asset.heading),
                clientId: Value(asset.clientId),
                version: Value(asset.version),
                updatedAt: DateTime.now(),
                syncStatus: const Value('synced'),
              ),
            );
      }

      return PullResult(assetCount: assets.length);
    } catch (_) {
      return PullResult(assetCount: 0);
    }
  }

  Future<void> enqueueChange({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final clientId = _uuid.v4();
    await _db.enqueueSyncItem(
      SyncQueueItemsCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        clientId: clientId,
        operation: operation,
        payloadJson: jsonEncode(payload),
        status: const Value('pending'),
        createdAt: DateTime.now(),
      ),
    );
  }
}

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.skipped = false,
  });

  final int pushed;
  final int pulled;
  final int conflicts;
  final int failed;
  final bool skipped;
}

class PushResult {
  const PushResult({
    required this.synced,
    required this.conflicts,
    required this.failed,
  });

  final List<String> synced;
  final List<String> conflicts;
  final List<String> failed;
}

class PullResult {
  const PullResult({required this.assetCount});
  final int assetCount;
}
