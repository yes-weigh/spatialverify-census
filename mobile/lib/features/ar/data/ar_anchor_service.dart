import 'dart:math';
import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_engine.dart';

class ArAnchorService {
  ArAnchorService({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncEngine syncEngine,
  })  : _api = apiClient,
        _db = database,
        _sync = syncEngine;

  final ApiClient _api;
  final AppDatabase _db;
  final SyncEngine _sync;
  final _uuid = const Uuid();

  final List<SpatialAnchor> _activeAnchors = [];

  List<SpatialAnchor> get activeAnchors => List.unmodifiable(_activeAnchors);

  Future<SpatialAnchor> createAnchor({
    required String projectId,
    required String anchorId,
    required double latitude,
    required double longitude,
    String? assetId,
    double? altitude,
    double? heading,
    Map<String, double>? cameraOrientation,
    Map<String, dynamic>? anchorData,
    String? assetName,
    String? status,
    double? confidence,
  }) async {
    final id = _uuid.v4();
    final clientId = _uuid.v4();

    final anchor = SpatialAnchor(
      id: id,
      anchorId: anchorId,
      assetId: assetId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      heading: heading,
      cameraOrientation: cameraOrientation,
      assetName: assetName,
      status: status,
      confidence: confidence,
    );

    _activeAnchors.add(anchor);

    await _db.into(_db.localAnchors).insert(
          LocalAnchorsCompanion.insert(
            id: id,
            projectId: projectId,
            assetId: Value(assetId),
            anchorId: anchorId,
            latitude: latitude,
            longitude: longitude,
            altitude: Value(altitude),
            heading: Value(heading),
            cameraOrientationJson: Value(
              cameraOrientation != null ? cameraOrientation.toString() : null,
            ),
            clientId: Value(clientId),
          ),
        );

    await _sync.enqueueChange(
      entityType: 'anchor',
      entityId: id,
      operation: 'create',
      payload: {
        'project_id': projectId,
        'asset_id': assetId,
        'anchor_id': anchorId,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'heading': heading,
        'camera_orientation': cameraOrientation,
        'anchor_data': anchorData ?? {},
      },
    );

    try {
      await _api.post('/survey/anchors', data: {
        'projectId': projectId,
        'assetId': assetId,
        'anchorId': anchorId,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'heading': heading,
        'cameraOrientation': cameraOrientation,
        'anchorData': anchorData,
        'clientId': clientId,
      });
    } catch (_) {}

    return anchor;
  }

  Future<void> relocateAnchor({
    required String anchorId,
    required double latitude,
    required double longitude,
    double? altitude,
    double? heading,
    Map<String, double>? cameraOrientation,
  }) async {
    final index = _activeAnchors.indexWhere((a) => a.anchorId == anchorId);
    if (index >= 0) {
      final existing = _activeAnchors[index];
      _activeAnchors[index] = SpatialAnchor(
        id: existing.id,
        anchorId: anchorId,
        assetId: existing.assetId,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude ?? existing.altitude,
        heading: heading ?? existing.heading,
        cameraOrientation: cameraOrientation ?? existing.cameraOrientation,
        assetName: existing.assetName,
        status: existing.status,
        confidence: existing.confidence,
      );
    }

    try {
      await _api.patch('/survey/anchors/${_activeAnchors[index].id}/relocate', data: {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'heading': heading,
        'cameraOrientation': cameraOrientation,
      });
    } catch (_) {}
  }

  void updateDistances(Position userPosition) {
    for (var i = 0; i < _activeAnchors.length; i++) {
      final anchor = _activeAnchors[i];
      final distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        anchor.latitude,
        anchor.longitude,
      );
      _activeAnchors[i] = SpatialAnchor(
        id: anchor.id,
        anchorId: anchor.anchorId,
        assetId: anchor.assetId,
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        altitude: anchor.altitude,
        heading: anchor.heading,
        cameraOrientation: anchor.cameraOrientation,
        assetName: anchor.assetName,
        status: anchor.status,
        confidence: anchor.confidence,
        distance: distance,
      );
    }
  }

  Future<void> loadAnchorsForProject(String projectId) async {
    try {
      final response = await _api.get('/survey/anchors/project/$projectId');
      final list = (response.data as List<dynamic>);
      _activeAnchors.clear();
      for (final data in list) {
        final json = data as Map<String, dynamic>;
        _activeAnchors.add(SpatialAnchor(
          id: json['id'] as String,
          anchorId: json['anchor_id'] as String,
          assetId: json['asset_id'] as String?,
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
          altitude: (json['altitude'] as num?)?.toDouble(),
          heading: (json['heading'] as num?)?.toDouble(),
        ));
      }
    } catch (_) {
      final cached = await (_db.select(_db.localAnchors)
            ..where((a) => a.projectId.equals(projectId)))
          .get();
      _activeAnchors.clear();
      for (final a in cached) {
        _activeAnchors.add(SpatialAnchor(
          id: a.id,
          anchorId: a.anchorId,
          assetId: a.assetId,
          latitude: a.latitude,
          longitude: a.longitude,
          altitude: a.altitude,
          heading: a.heading,
        ));
      }
    }
  }

  void clear() {
    _activeAnchors.clear();
  }
}
