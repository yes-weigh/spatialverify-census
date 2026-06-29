import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../scanner/data/object_detector.dart';
import '../data/mission_intelligence_engine.dart';
import '../data/mission_local_first_service.dart';
import '../data/hlb_local_state.dart';
import '../models/mission_models.dart';
import '../models/discovery_models.dart';
import '../data/hlb_official_catalog.dart';
import '../widgets/discovery_confirm_sheet.dart';
import '../widgets/discovery_mini_map.dart';
import '../widgets/discovery_overlay.dart';
import 'mission_providers.dart';
import '../widgets/bearing_arrow.dart';

/// Full-screen camera discovery — human-operated spatial scanner.
class DiscoveryCameraScreen extends ConsumerStatefulWidget {
  const DiscoveryCameraScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<DiscoveryCameraScreen> createState() => _DiscoveryCameraScreenState();
}

class _DiscoveryCameraScreenState extends ConsumerState<DiscoveryCameraScreen> with MissionGpsTracking {
  CameraController? _camera;
  final _detector = ObjectDetector();
  List<DiscoveryCandidate> _candidates = [];
  final _handledHypothesisIds = <String>{};
  HlbLocalState? _missionState;
  DiscoveryCandidate? _nearestPrediction;
  bool _scanning = true;
  bool _processingFrame = false;

  MissionLocalFirstService get _local => ref.read(missionLocalFirstProvider);
  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _detector.loadModel();
    await ensureLocationPermission();
    await _initCamera();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (_) {
        _refreshSatellitePredictions();
      },
      onBreadcrumb: (pos) {
        _local.addBreadcrumb(widget.ebId, pos.latitude, pos.longitude, accuracy: pos.accuracy);
        _invalidateDiscovery();
      },
    );
    final state = await _local.getRawState(widget.ebId);
    _missionState = state;
    if (state?.hasOfficialBoundary == true) {
      await _local.recordBoundaryAudit(widget.ebId, 'discovery_started');
    }
    await _startDetectionStream();
  }

  void _refreshSatellitePredictions() {
    final pos = position;
    final state = _missionState;
    if (pos == null || state == null) return;
    final satellite = MissionIntelligenceEngine.nearbyPredictions(
      state,
      pos.latitude,
      pos.longitude,
      handledIds: _handledHypothesisIds,
    );
    _nearestPrediction = satellite.isNotEmpty ? satellite.first : null;
    final merged = MissionIntelligenceEngine.merge(_candidates.where((c) => c.source == 'camera').toList(), satellite);
    if (merged.length != _candidates.length) {
      setState(() => _candidates = merged);
    } else {
      setState(() => _nearestPrediction = satellite.isNotEmpty ? satellite.first : null);
    }
  }

  void _invalidateDiscovery() {
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
    ref.invalidate(hlbAnalyticsProvider(_query));
  }

  Future<void> _startDetectionStream() async {
    if (_camera == null || !_camera!.value.isInitialized) return;
    try {
      await _camera!.startImageStream(_onCameraFrame);
    } catch (_) {}
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (!_scanning || _processingFrame) return;
    _processingFrame = true;
    try {
      final detections = await _detector.detect(image, 0);
      if (!mounted) return;
      final pos = position;
      final state = _missionState ?? await _local.getRawState(widget.ebId);
      _missionState = state;
      final heading = pos?.heading;
      final mapped = <DiscoveryCandidate>[];
      for (final d in detections) {
        final id = '${d.label}_${d.boundingBox.x.toStringAsFixed(2)}_${d.boundingBox.y.toStringAsFixed(2)}';
        final existing = _candidates.where((c) => c.id == id).firstOrNull;
        if (existing?.status == DiscoveryCandidateStatus.rejected) continue;
        final candidate = DiscoveryCandidate.fromDetection(
          d,
          id: id,
          latitude: pos?.latitude,
          longitude: pos?.longitude,
          heading: heading != null && heading >= 0 ? heading : null,
        ).copyWith(status: existing?.status ?? DiscoveryCandidateStatus.suggested);
        if (!candidate.showOnCamera) continue;
        mapped.add(candidate);
      }
      final satellite = state != null && pos != null
          ? MissionIntelligenceEngine.nearbyPredictions(
              state,
              pos.latitude,
              pos.longitude,
              handledIds: _handledHypothesisIds,
            )
          : <DiscoveryCandidate>[];
      final merged = MissionIntelligenceEngine.merge(mapped, satellite);
      setState(() {
        _candidates = merged;
        _nearestPrediction = satellite.isNotEmpty ? satellite.first : null;
      });
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _camera = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    await _camera!.initialize();
    if (mounted) setState(() {});
    await _startDetectionStream();
  }

  /// Single tap — quick confirm with defaults (□ Pucca Residential, 1 census house).
  Future<void> _onQuickConfirm(DiscoveryCandidate c) async {
    if (c.status != DiscoveryCandidateStatus.suggested) return;
    if (position == null) return;
    if (!await _ensureInsideBoundary()) return;

    if (c.type == DiscoveryObjectType.building) {
      final num = await _local.quickConfirmStructure(
        widget.ebId,
        latitude: position!.latitude,
        longitude: position!.longitude,
      );
      _markCandidate(c.id, DiscoveryCandidateStatus.confirmed);
      if (c.hypothesisId != null) _handledHypothesisIds.add(c.hypothesisId!);
      _invalidateDiscovery();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CN-${num.toString().padLeft(3, '0')} confirmed · □ Pucca Residential'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (c.type == DiscoveryObjectType.landmark) {
      final name = c.label.isNotEmpty ? c.label : 'Map feature';
      final landmarkType = HlbOfficialCatalog.guessLandmarkTypeFromLabel(c.label);
      await _local.discoverLandmark(
        widget.ebId,
        name: name,
        landmarkType: landmarkType,
        latitude: position!.latitude,
        longitude: position!.longitude,
      );
      await _local.addSpatialObservation(
        widget.ebId,
        type: 'landmark',
        latitude: position!.latitude,
        longitude: position!.longitude,
        heading: position!.heading >= 0 ? position!.heading : null,
        label: name,
      );
      _markCandidate(c.id, DiscoveryCandidateStatus.confirmed);
      if (c.hypothesisId != null) _handledHypothesisIds.add(c.hypothesisId!);
      _invalidateDiscovery();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name confirmed'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  /// Long press — full details sheet.
  Future<void> _onOpenDetails(DiscoveryCandidate c) async {
    if (c.status != DiscoveryCandidateStatus.suggested) return;
    if (position == null) return;
    if (!await _ensureInsideBoundary(allowCancel: true)) return;

    final suggested = await _local.suggestBuildingNumber(widget.ebId, position!.latitude, position!.longitude);
    final label = 'CN-${suggested.toString().padLeft(3, '0')}';

    if (c.type == DiscoveryObjectType.building) {
      await DiscoveryConfirmSheet.show(
        context,
        candidate: c,
        suggestedNumber: suggested,
        suggestedLabel: label,
        onConfirm: ({required buildingType, required buildingNumber, required censusHouseCount, String? featureLabel}) async {
          await _local.discoverBuilding(
            widget.ebId,
            latitude: position!.latitude,
            longitude: position!.longitude,
            buildingType: buildingType,
            buildingNumber: buildingNumber,
            censusHouseCount: censusHouseCount,
          );
          await _local.addSpatialObservation(
            widget.ebId,
            type: 'building',
            latitude: position!.latitude,
            longitude: position!.longitude,
            heading: position!.heading >= 0 ? position!.heading : null,
            linkedEntityId: buildingNumber.toString(),
            label: label,
          );
          _markCandidate(c.id, DiscoveryCandidateStatus.confirmed);
          _invalidateDiscovery();
        },
        onReject: () => _onIgnore(c),
      );
    } else if (c.type == DiscoveryObjectType.landmark) {
      await DiscoveryConfirmSheet.show(
        context,
        candidate: c,
        suggestedNumber: 0,
        suggestedLabel: '',
        onConfirm: ({required buildingType, required buildingNumber, required censusHouseCount, String? featureLabel}) async {
          final name = (featureLabel?.isNotEmpty ?? false) ? featureLabel! : (c.label.isNotEmpty ? c.label : 'Map feature');
          await _local.discoverLandmark(
            widget.ebId,
            name: name,
            landmarkType: buildingType.isEmpty ? 'other' : buildingType,
            latitude: position!.latitude,
            longitude: position!.longitude,
          );
          await _local.addSpatialObservation(
            widget.ebId,
            type: 'landmark',
            latitude: position!.latitude,
            longitude: position!.longitude,
            heading: position!.heading >= 0 ? position!.heading : null,
            label: c.label,
          );
          _markCandidate(c.id, DiscoveryCandidateStatus.confirmed);
          _invalidateDiscovery();
        },
        onReject: () => _onIgnore(c),
      );
    }
  }

  Future<void> _onIgnore(DiscoveryCandidate c) async {
    if (position == null) return;
    if (c.hypothesisId != null) _handledHypothesisIds.add(c.hypothesisId!);
    await _local.recordIgnoredSuggestion(
      widget.ebId,
      id: c.id,
      label: c.typeLabel,
      latitude: position!.latitude,
      longitude: position!.longitude,
    );
    _markCandidate(c.id, DiscoveryCandidateStatus.rejected);
    _invalidateDiscovery();
  }

  /// Returns false if user cancels an outside-boundary override.
  Future<bool> _ensureInsideBoundary({bool allowCancel = false}) async {
    final state = await _local.getRawState(widget.ebId);
    if (state == null || !state.hasOfficialBoundary || position == null) return true;
    if (_local.isInsideOfficialBoundary(state, position!.latitude, position!.longitude)) {
      await _local.recordBoundaryAudit(widget.ebId, 'entered');
      return true;
    }

    final override = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Outside assigned HLB'),
        content: const Text(
          'This structure appears outside your official HLB boundary.\n\n'
          'Confirm only if you are certain it belongs to this block.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Confirm Anyway'),
          ),
        ],
      ),
    );
    if (override != true) return false;

    await _local.recordOutsideBoundaryDiscovery(
      widget.ebId,
      latitude: position!.latitude,
      longitude: position!.longitude,
      label: 'Structure outside boundary',
      overridden: true,
    );
    return true;
  }

  void _markCandidate(String id, DiscoveryCandidateStatus status) {
    setState(() {
      _candidates = _candidates.map((c) => c.id == id ? c.copyWith(status: status) : c).toList();
    });
  }

  @override
  void dispose() {
    if (_camera?.value.isStreamingImages == true) {
      _camera!.stopImageStream();
    }
    _camera?.dispose();
    _detector.dispose();
    stopMissionGps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final mapAsync = ref.watch(draftMapProvider(_query));
    final analyticsAsync = ref.watch(hlbAnalyticsProvider(_query));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camera?.value.isInitialized == true)
            CameraPreview(_camera!)
          else
            const Center(child: CircularProgressIndicator()),
          DiscoveryOverlay(
            candidates: _candidates,
            onQuickConfirm: _onQuickConfirm,
            onOpenDetails: _onOpenDetails,
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  discoveryAsync: discoveryAsync,
                  nearestPrediction: _nearestPrediction,
                  onClose: () => context.pop(),
                  onDashboard: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/dashboard'),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      mapAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (map) => analyticsAsync.when(
                          loading: () => DiscoveryMiniMap(mapData: map, heatmapCells: const []),
                          error: (_, __) => DiscoveryMiniMap(mapData: map, heatmapCells: const []),
                          data: (a) => DiscoveryMiniMap(
                            mapData: map,
                            heatmapCells: a.heatmap,
                            streets: a.streets,
                            onExpand: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/draft-map'),
                          ),
                        ),
                      ),
                      const Spacer(),
                      _ScanModeToggle(
                        spatialScan: _scanning,
                        onToggle: () => setState(() => _scanning = !_scanning),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.discoveryAsync,
    required this.onClose,
    required this.onDashboard,
    this.nearestPrediction,
  });
  final AsyncValue<DiscoveryStatus> discoveryAsync;
  final VoidCallback onClose;
  final VoidCallback onDashboard;
  final DiscoveryCandidate? nearestPrediction;

  @override
  Widget build(BuildContext context) {
    final pred = nearestPrediction;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: onClose),
              Expanded(
                child: discoveryAsync.when(
                  loading: () => const Text('Scanning…', style: TextStyle(color: Colors.white)),
                  error: (_, __) => const Text('Discovery Walk', style: TextStyle(color: Colors.white)),
                  data: (d) => Text(
                    'Structures: ${d.buildingsDiscovered} · Road layer on map',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.dashboard_outlined, color: Colors.white), onPressed: onDashboard),
            ],
          ),
        ),
        if (pred != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2218),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Predicted observation target ${pred.distanceMeters?.round() ?? '?'}m away — validate when visible',
              style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

class _ScanModeToggle extends StatelessWidget {
  const _ScanModeToggle({required this.spatialScan, required this.onToggle});
  final bool spatialScan;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FloatingActionButton.extended(
          onPressed: onToggle,
          backgroundColor: spatialScan ? const Color(0xFF42A5F5) : Colors.grey.shade800,
          icon: Icon(spatialScan ? Icons.radar : Icons.radar_outlined),
          label: Text(spatialScan ? 'Spatial Scan' : 'Paused'),
        ),
        const SizedBox(height: 8),
        const Text('Tap confirm · Hold details', style: TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
