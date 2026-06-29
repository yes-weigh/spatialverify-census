import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/sync/sync_engine.dart';
import 'object_detector.dart';

class DetectionService {
  DetectionService({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncEngine syncEngine,
    ObjectDetector? detector,
  })  : _api = apiClient,
        _db = database,
        _sync = syncEngine,
        _detector = detector ?? ObjectDetector();

  final ApiClient _api;
  final AppDatabase _db;
  final SyncEngine _sync;
  final ObjectDetector _detector;
  final _uuid = const Uuid();

  bool _initialized = false;
  List<AssetCategory> _categories = [];

  Future<void> initialize(List<AssetCategory> categories) async {
    _categories = categories;
    if (!_initialized) {
      await _detector.loadModel();
      _initialized = true;
    }
  }

  Future<List<DetectedObject>> processFrame(
    CameraImage image,
    int rotation,
  ) async {
    if (!_initialized) return [];

    final detections = await _detector.detect(image, rotation);
    return detections
        .where((d) => d.confidence >= AppConfig.minDetectionConfidence)
        .toList();
  }

  Future<Detection> saveDetection({
    required String projectId,
    required String sessionId,
    required DetectedObject detected,
    required Position position,
  }) async {
    final id = _uuid.v4();
    final clientId = _uuid.v4();

    final detection = Detection(
      id: id,
      categoryLabel: detected.label,
      confidence: detected.confidence,
      boundingBox: detected.boundingBox,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      heading: position.heading,
      clientId: clientId,
    );

    await _db.into(_db.localDetections).insert(
          LocalDetectionsCompanion.insert(
            id: id,
            projectId: projectId,
            sessionId: Value(sessionId),
            categoryLabel: detected.label,
            confidence: detected.confidence,
            boundingBoxJson: jsonEncode(detected.boundingBox.toJson()),
            latitude: Value(position.latitude),
            longitude: Value(position.longitude),
            altitude: Value(position.altitude),
            heading: Value(position.heading),
            clientId: Value(clientId),
            createdAt: DateTime.now(),
          ),
        );

    await _sync.enqueueChange(
      entityType: 'detection',
      entityId: id,
      operation: 'create',
      payload: {
        'project_id': projectId,
        'session_id': sessionId,
        'category_label': detected.label,
        'confidence': detected.confidence,
        'bounding_box': detected.boundingBox.toJson(),
        'location': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
        'altitude': position.altitude,
        'heading': position.heading,
      },
    );

    try {
      final response = await _api.post('/detections/project/$projectId', data: {
        'sessionId': sessionId,
        'categoryLabel': detected.label,
        'confidence': detected.confidence,
        'boundingBox': detected.boundingBox.toJson(),
        'location': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
        'altitude': position.altitude,
        'heading': position.heading,
        'clientId': clientId,
      });
      return Detection.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return detection;
    }
  }

  Future<Map<String, dynamic>> verifyDetection({
    required String detectionId,
    required HumanDecision decision,
    String? editedCategory,
    double? editedLat,
    double? editedLng,
    String? notes,
    String? matchedAssetId,
    String? identityResolutionId,
    List<double>? embedding,
  }) async {
    final decisionStr = decision.name;
    final clientId = _uuid.v4();

    await _db.into(_db.localVerifications).insert(
          LocalVerificationsCompanion.insert(
            id: _uuid.v4(),
            detectionId: detectionId,
            aiPrediction: editedCategory ?? '',
            confidence: 0,
            humanDecision: decisionStr,
            editedCategory: Value(editedCategory),
            editedLat: Value(editedLat),
            editedLng: Value(editedLng),
            notes: Value(notes),
            clientId: Value(clientId),
            verifiedAt: DateTime.now(),
          ),
        );

    try {
      final response = await _api.post('/detections/$detectionId/verify', data: {
        'humanDecision': decisionStr,
        if (editedCategory != null) 'editedCategory': editedCategory,
        if (editedLat != null && editedLng != null)
          'editedLocation': {
            'type': 'Point',
            'coordinates': [editedLng, editedLat],
          },
        if (notes != null) 'notes': notes,
        'clientId': clientId,
        if (matchedAssetId != null) 'matchedAssetId': matchedAssetId,
        if (identityResolutionId != null) 'identityResolutionId': identityResolutionId,
        if (embedding != null) 'embedding': embedding,
      });
      return response.data as Map<String, dynamic>;
    } catch (e) {
      return {'offline': true, 'clientId': clientId};
    }
  }

  void dispose() {
    _detector.dispose();
  }
}
