import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../scanner/data/object_detector.dart';
import '../../identity/data/spatial_identity_service.dart';
import '../../mission/models/mission_models.dart';
import '../../mission/presentation/eb_list_screen.dart';
import '../../mission/presentation/mission_home_screen.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/verification_card.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({
    required this.projectId,
    this.ebId,
    this.buildingId,
    super.key,
  });

  final String projectId;
  final String? ebId;
  final String? buildingId;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _cameraController;
  List<DetectedObject> _detections = [];
  DetectedObject? _selectedDetection;
  Position? _currentPosition;
  bool _isProcessing = false;
  Timer? _detectionTimer;
  String? _sessionId;
  CameraImage? _lastCameraImage;
  IdentityResult? _identityResult;
  List<double>? _currentEmbedding;
  bool _isResolvingIdentity = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startLocationTracking();
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post('/survey/sessions', data: {
        'projectId': widget.projectId,
      });
      _sessionId = (response.data as Map<String, dynamic>)['id'] as String;
    } catch (_) {
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();

    final categories = await ref
        .read(projectRepositoryProvider)
        .getCategories(widget.projectId);
    await ref.read(detectionServiceProvider).initialize(categories);
    await ref.read(spatialIdentityServiceProvider).initialize();

    if (mounted) {
      setState(() {});
      _startDetectionLoop();
    }
  }

  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (mounted) setState(() => _currentPosition = position);
    });
  }

  void _startDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) {
        return;
      }
      _isProcessing = true;
      try {
        await _cameraController!.startImageStream((image) async {
          _lastCameraImage = image;
          if (_isProcessing) {
            _isProcessing = false;
            final detections = await ref
                .read(detectionServiceProvider)
                .processFrame(image, _cameraController!.description.sensorOrientation);
            if (mounted && detections.isNotEmpty) {
              setState(() => _detections = detections);
            }
          }
        });
      } catch (_) {
        _isProcessing = false;
      }
    });
  }

  Future<void> _onDetectionTap(DetectedObject detection) async {
    setState(() {
      _selectedDetection = detection;
      _identityResult = null;
      _currentEmbedding = null;
      _isResolvingIdentity = true;
    });

    if (_lastCameraImage != null && _currentPosition != null) {
      final identityService = ref.read(spatialIdentityServiceProvider);
      final embedding = await identityService.generateEmbedding(
        _lastCameraImage!,
        _cameraController!.description.sensorOrientation,
      );

      final result = await identityService.resolveIdentity(
        projectId: widget.projectId,
        categoryLabel: detection.label,
        position: _currentPosition!,
        embedding: embedding,
        viewType: ViewType.unknown,
        cameraController: _cameraController,
        cameraDescription: _cameraController?.description,
      );

      if (mounted) {
        setState(() {
          _identityResult = result;
          _currentEmbedding = embedding;
          _isResolvingIdentity = false;
        });
      }
    } else if (mounted) {
      setState(() => _isResolvingIdentity = false);
    }
  }

  Future<void> _handleVerification(HumanDecision decision, {String? editedCategory}) async {
    if (_selectedDetection == null || _currentPosition == null || _sessionId == null) return;

    final service = ref.read(detectionServiceProvider);
    final saved = await service.saveDetection(
      projectId: widget.projectId,
      sessionId: _sessionId!,
      detected: _selectedDetection!,
      position: _currentPosition!,
    );

    if (decision != HumanDecision.rejected &&
        _identityResult?.verdict == IdentityVerdict.possibleMatch) {
      await ref.read(spatialIdentityServiceProvider).confirmResolution(
            _identityResult!.resolutionId,
            linkToAssetId: _identityResult!.matchedAssetId,
          );
    }

    await service.verifyDetection(
      detectionId: saved.id,
      decision: decision,
      editedCategory: editedCategory ?? _selectedDetection!.label,
      editedLat: _currentPosition!.latitude,
      editedLng: _currentPosition!.longitude,
      matchedAssetId: _identityResult?.verdict == IdentityVerdict.sameAsset ||
              _identityResult?.verdict == IdentityVerdict.possibleMatch
          ? _identityResult!.matchedAssetId
          : null,
      identityResolutionId: _identityResult?.resolutionId,
      embedding: _currentEmbedding,
    );

    if (decision != HumanDecision.rejected &&
        widget.buildingId != null &&
        widget.ebId != null) {
      await ref.read(missionApiProvider).updateBuildingStatus(
            widget.buildingId!,
            MissionBuildingStatus.completed,
            assetId: _identityResult?.matchedAssetId,
          );
      ref.invalidate(missionRouteProvider(widget.ebId!));
      ref.invalidate(missionDashboardProvider);
      ref.invalidate(missionCoverageProvider(widget.ebId!));
    }

    if (mounted) {
      final verdict = _identityResult?.verdict;
      setState(() {
        _selectedDetection = null;
        _identityResult = null;
        _currentEmbedding = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == HumanDecision.rejected
                ? 'Detection rejected'
                : widget.buildingId != null
                    ? 'Building verified and marked complete'
                    : verdict == IdentityVerdict.sameAsset
                        ? 'Linked to existing asset'
                        : 'Detection verified',
          ),
        ),
      );
      if (widget.buildingId != null && widget.ebId != null && decision != HumanDecision.rejected) {
        context.pop();
      }
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          DetectionOverlay(
            detections: _detections,
            onDetectionTap: _onDetectionTap,
          ),
          if (_selectedDetection != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VerificationCard(
                detection: _selectedDetection!,
                position: _currentPosition,
                identityResult: _identityResult,
                isResolvingIdentity: _isResolvingIdentity,
                onConfirm: () => _handleVerification(HumanDecision.confirmed),
                onReject: () => _handleVerification(HumanDecision.rejected),
                onEdit: (category) =>
                    _handleVerification(HumanDecision.edited, editedCategory: category),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _ScannerHeader(
              detectionCount: _detections.length,
              hasGps: _currentPosition != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerHeader extends StatelessWidget {
  const _ScannerHeader({
    required this.detectionCount,
    required this.hasGps,
  });

  final int detectionCount;
  final bool hasGps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: AppTheme.glassDecoration(radius: 20),
      child: Row(
        children: [
          Icon(
            Icons.radar,
            color: detectionCount > 0 ? AppTheme.primary : AppTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            '$detectionCount detected',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          ),
          const Spacer(),
          Icon(
            hasGps ? Icons.gps_fixed : Icons.gps_off,
            color: hasGps ? AppTheme.verified : AppTheme.rejected,
            size: 20,
          ),
        ],
      ),
    );
  }
}
