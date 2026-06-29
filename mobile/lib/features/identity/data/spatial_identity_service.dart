import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_engine.dart';
import 'embedding_service.dart';
import 'device_capture_service.dart';

enum IdentityVerdict { sameAsset, possibleMatch, newAsset }

enum ViewType { front, left, right, rear, far, unknown }

extension ViewTypeApi on ViewType {
  String get apiValue => name;

  static ViewType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'front':
        return ViewType.front;
      case 'left':
        return ViewType.left;
      case 'right':
        return ViewType.right;
      case 'rear':
        return ViewType.rear;
      case 'far':
        return ViewType.far;
      default:
        return ViewType.unknown;
    }
  }
}

class ConfidenceExplanation {
  const ConfidenceExplanation({
    required this.gps,
    required this.embedding,
    required this.category,
    required this.heading,
    this.gpsAccuracyFactor,
    this.insideCluster,
    this.bestView,
    this.summary,
    this.visualDrift,
    this.lastSeenAt,
    this.clusterRadiusM,
    this.distanceToCentroidM,
  });

  final double gps;
  final double embedding;
  final double category;
  final double heading;
  final double? gpsAccuracyFactor;
  final bool? insideCluster;
  final String? bestView;
  final String? summary;
  final double? visualDrift;
  final String? lastSeenAt;
  final double? clusterRadiusM;
  final double? distanceToCentroidM;

  factory ConfidenceExplanation.fromJson(Map<String, dynamic> json) {
    return ConfidenceExplanation(
      gps: (json['gps'] as num?)?.toDouble() ?? 0,
      embedding: (json['embedding'] as num?)?.toDouble() ?? 0,
      category: (json['category'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      gpsAccuracyFactor: (json['gps_accuracy_factor'] as num?)?.toDouble(),
      insideCluster: json['inside_cluster'] as bool?,
      bestView: json['best_view'] as String?,
      summary: json['summary'] as String?,
      visualDrift: (json['visual_drift'] as num?)?.toDouble(),
      lastSeenAt: json['last_seen_at'] as String?,
      clusterRadiusM: (json['cluster_radius_m'] as num?)?.toDouble(),
      distanceToCentroidM: (json['distance_to_centroid_m'] as num?)?.toDouble(),
    );
  }
}

class IdentityResult {
  const IdentityResult({
    required this.resolutionId,
    required this.verdict,
    this.matchedAssetId,
    required this.finalConfidence,
    required this.scores,
    required this.requiresReview,
    this.conflictId,
    this.matchedAssetName,
    this.explanation,
  });

  final String resolutionId;
  final IdentityVerdict verdict;
  final String? matchedAssetId;
  final double finalConfidence;
  final Map<String, double> scores;
  final bool requiresReview;
  final String? conflictId;
  final String? matchedAssetName;
  final ConfidenceExplanation? explanation;

  factory IdentityResult.fromJson(Map<String, dynamic> json) {
    final verdictStr = (json['verdict'] as String).toLowerCase();
    IdentityVerdict verdict;
    switch (verdictStr) {
      case 'same_asset':
        verdict = IdentityVerdict.sameAsset;
      case 'possible_match':
        verdict = IdentityVerdict.possibleMatch;
      default:
        verdict = IdentityVerdict.newAsset;
    }

    final scoresJson = json['scores'] as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>?;
    String? matchedName;
    if (candidates != null && candidates.isNotEmpty) {
      matchedName = candidates[0]['asset_name'] as String?;
    }

    return IdentityResult(
      resolutionId: json['resolutionId'] as String,
      verdict: verdict,
      matchedAssetId: json['matchedAssetId'] as String?,
      finalConfidence: (json['finalConfidence'] as num).toDouble(),
      scores: scoresJson.map((k, v) => MapEntry(k, (v as num).toDouble())),
      requiresReview: json['requiresReview'] as bool? ?? false,
      conflictId: json['conflictId'] as String?,
      matchedAssetName: matchedName,
      explanation: json['explanation'] != null
          ? ConfidenceExplanation.fromJson(json['explanation'] as Map<String, dynamic>)
          : null,
    );
  }

  String get verdictLabel {
    switch (verdict) {
      case IdentityVerdict.sameAsset:
        return 'SAME_ASSET';
      case IdentityVerdict.possibleMatch:
        return 'POSSIBLE_MATCH';
      case IdentityVerdict.newAsset:
        return 'NEW_ASSET';
    }
  }
}

class SpatialIdentityService {
  SpatialIdentityService({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncEngine syncEngine,
    EmbeddingService? embeddingService,
    DeviceCaptureService? deviceCaptureService,
  })  : _api = apiClient,
        _db = database,
        _sync = syncEngine,
        _embedding = embeddingService ?? EmbeddingService(),
        _deviceCapture = deviceCaptureService ?? DeviceCaptureService();

  final ApiClient _api;
  final AppDatabase _db;
  final SyncEngine _sync;
  final EmbeddingService _embedding;
  final DeviceCaptureService _deviceCapture;
  final _uuid = const Uuid();

  Future<void> initialize() async {
    await _embedding.loadModel();
  }

  Future<List<double>> generateEmbedding(CameraImage image, int rotation) {
    return _embedding.generateFromCameraImage(image, rotation);
  }

  Future<IdentityResult> resolveIdentity({
    required String projectId,
    required String categoryLabel,
    required Position position,
    required List<double> embedding,
    String? detectionId,
    String? clientId,
    ViewType viewType = ViewType.unknown,
    String? weather,
    String? lighting,
    DeviceCaptureMetadata? deviceMetadata,
    CameraController? cameraController,
    CameraDescription? cameraDescription,
  }) async {
    final device = deviceMetadata ??
        await _deviceCapture.capture(
          controller: cameraController,
          description: cameraDescription,
        );

    final payload = {
      'projectId': projectId,
      'categoryLabel': categoryLabel,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'heading': position.heading,
      'accuracy': position.accuracy,
      'viewType': viewType.apiValue,
      'embedding': embedding,
      ...device.toPayload(),
      if (detectionId != null) 'detectionId': detectionId,
      if (clientId != null) 'clientId': clientId,
      if (weather != null) 'weather': weather,
      if (lighting != null) 'lighting': lighting,
    };

    await _cacheObservationLocally(
      projectId: projectId,
      categoryLabel: categoryLabel,
      embedding: embedding,
      position: position,
      detectionId: detectionId,
      viewType: viewType,
      weather: weather,
      lighting: lighting,
      deviceMetadata: device,
    );

    await _cacheResolutionLocally(
      projectId: projectId,
      categoryLabel: categoryLabel,
      embedding: embedding,
      detectionId: detectionId,
      payload: payload,
    );

    try {
      final response = await _api.post('/identity/resolve', data: payload);
      return IdentityResult.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return _offlineResolve(embedding, categoryLabel);
    }
  }

  Future<void> storeObservation({
    required String projectId,
    required List<double> embedding,
    required Position position,
    String? assetId,
    String? detectionId,
    String? categoryLabel,
    ViewType viewType = ViewType.unknown,
    String? weather,
    String? lighting,
    DeviceCaptureMetadata? deviceMetadata,
    CameraController? cameraController,
    CameraDescription? cameraDescription,
  }) async {
    final device = deviceMetadata ??
        await _deviceCapture.capture(
          controller: cameraController,
          description: cameraDescription,
        );

    final payload = {
      'projectId': projectId,
      'embedding': embedding,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'heading': position.heading,
      'viewType': viewType.apiValue,
      ...device.toPayload(),
      if (assetId != null) 'assetId': assetId,
      if (detectionId != null) 'detectionId': detectionId,
      if (categoryLabel != null) 'categoryLabel': categoryLabel,
      if (weather != null) 'weather': weather,
      if (lighting != null) 'lighting': lighting,
    };

    await _cacheObservationLocally(
      projectId: projectId,
      categoryLabel: categoryLabel ?? '',
      embedding: embedding,
      position: position,
      detectionId: detectionId,
      assetId: assetId,
      viewType: viewType,
      weather: weather,
      lighting: lighting,
      deviceMetadata: device,
    );

    try {
      await _api.post('/identity/observations', data: payload);
    } catch (_) {
      await _sync.enqueueChange(
        entityType: 'asset_observation',
        entityId: _uuid.v4(),
        operation: 'create',
        payload: payload,
      );
    }
  }

  Future<void> confirmResolution(String resolutionId, {String? linkToAssetId}) async {
    try {
      await _api.post('/identity/resolutions/$resolutionId/confirm', data: {
        if (linkToAssetId != null) 'linkToAssetId': linkToAssetId,
      });
    } catch (_) {
      await _sync.enqueueChange(
        entityType: 'identity_resolution',
        entityId: resolutionId,
        operation: 'update',
        payload: {'action': 'confirm', 'linkToAssetId': linkToAssetId},
      );
    }
  }

  Future<void> rejectResolution(String resolutionId) async {
    try {
      await _api.post('/identity/resolutions/$resolutionId/reject');
    } catch (_) {
      await _sync.enqueueChange(
        entityType: 'identity_resolution',
        entityId: resolutionId,
        operation: 'update',
        payload: {'action': 'reject'},
      );
    }
  }

  IdentityResult _offlineResolve(List<double> embedding, String category) {
    return IdentityResult(
      resolutionId: _uuid.v4(),
      verdict: IdentityVerdict.newAsset,
      finalConfidence: 0,
      scores: const {'gps': 0, 'embedding': 0, 'category': 0, 'heading': 0},
      requiresReview: false,
    );
  }

  Future<void> _cacheObservationLocally({
    required String projectId,
    required String categoryLabel,
    required List<double> embedding,
    required Position position,
    String? detectionId,
    String? assetId,
    ViewType viewType = ViewType.unknown,
    String? weather,
    String? lighting,
    DeviceCaptureMetadata? deviceMetadata,
  }) async {
    await _db.into(_db.localAssetObservations).insert(
          LocalAssetObservationsCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            assetId: Value(assetId),
            detectionId: Value(detectionId),
            embeddingJson: jsonEncode(embedding),
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: Value(position.altitude),
            accuracy: Value(position.accuracy),
            heading: Value(position.heading),
            viewType: Value(viewType.apiValue),
            categoryLabel: Value(categoryLabel.isEmpty ? null : categoryLabel),
            weather: Value(weather),
            lighting: Value(lighting),
            deviceModel: Value(deviceMetadata?.deviceModel),
            cameraFov: Value(deviceMetadata?.cameraFov),
            cameraResolution: Value(deviceMetadata?.cameraResolution),
            syncStatus: const Value('pending'),
            capturedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _cacheResolutionLocally({
    required String projectId,
    required String categoryLabel,
    required List<double> embedding,
    String? detectionId,
    required Map<String, dynamic> payload,
  }) async {
    await _db.into(_db.localIdentityResolutions).insert(
          LocalIdentityResolutionsCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            detectionId: Value(detectionId),
            queryCategory: categoryLabel,
            embeddingJson: jsonEncode(embedding),
            payloadJson: jsonEncode(payload),
            syncStatus: const Value('pending'),
            createdAt: DateTime.now(),
          ),
        );
  }

  void dispose() {
    _embedding.dispose();
  }
}
