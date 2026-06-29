import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/storage/mission_layout_storage.dart';
import '../../../core/maps/google_directions_service.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/boundary_rigid_align_math.dart';
import '../data/landmark_anchor_service.dart';
import '../data/local_mission_import_service.dart';
import '../data/mission_cv_worker.dart';
import '../data/mission_seed_location_resolver.dart';
import '../models/landmark_anchor_models.dart';
import '../models/manual_upload_draft.dart';
import '../models/pdf_georef_models.dart';
import '../widgets/hlo_pdf_georef_editor.dart';
import 'landmark_verification_panel.dart';
import '../data/layout_georef_service.dart';
import '../data/mission_local_first_service.dart';
import '../data/mission_map_helpers.dart';
import '../models/layout_georef_models.dart';
import '../widgets/boundary_corner_adjust_map.dart';
import '../widgets/bearing_arrow.dart';
import '../widgets/mission_layout_image.dart';
import '../widgets/mission_map_canvas.dart';
import '../widgets/mission_map_game_hud.dart';
import '../widgets/mission_navigation_banner.dart';
import '../widgets/mission_satellite_map.dart';
import 'mission_providers.dart';

final layoutGeorefApiProvider = Provider<LayoutGeorefApiService>((ref) {
  return LayoutGeorefApiService(apiClient: ref.watch(apiClientProvider));
});

enum _WizardPhase { upload, analyzing, pdfEditor, verifyLandmarks, mapExperience, adjust }

enum _AdjustFocus { pdfOverlay, boundary }

const _analysisSteps = [
  'Aligning to Google Maps…',
  'Projecting boundary…',
  'Loading observation regions…',
];

/// Import Official HLO Mission → full-screen satellite reveal → Mission Review.
class LayoutGeorefWizardScreen extends ConsumerStatefulWidget {
  const LayoutGeorefWizardScreen({
    required this.projectId,
    required this.ebId,
    this.restartAlignment = false,
    super.key,
  });

  final String projectId;
  final String ebId;
  final bool restartAlignment;

  @override
  ConsumerState<LayoutGeorefWizardScreen> createState() => _LayoutGeorefWizardScreenState();
}

class _LayoutGeorefWizardScreenState extends ConsumerState<LayoutGeorefWizardScreen>
    with TickerProviderStateMixin, MissionGpsTracking {
  _WizardPhase _phase = _WizardPhase.upload;
  String? _layoutImageUrl;
  MissionIntelligencePackage? _intelligence;
  LatLng? _mapCenter;
  ImageBounds? _imageBounds;
  var _opacity = 0.45;
  var _scaleFactor = 1.0;
  var _showMapPdfOverlay = true;
  var _showRegionPins = false;
  ImageBounds? _baseBounds;
  String? _error;
  String? _placementNotice;
  int _analysisStep = 0;
  Timer? _analysisTimer;

  MissionImportDraft? _importDraft;
  List<LandmarkMatchRow> _landmarkRows = [];

  ManualUploadDraft? _manualDraft;
  List<({double x, double y})> _boundaryRing = [];
  List<PdfGeorefPin> _pins = [];
  var _trackingBoundary = false;
  var _preparingPdf = false;

  double _boundaryProgress = 0;
  int _regionsVisible = 0;
  bool _boundaryComplete = false;
  bool _showReviewSheet = false;
  bool _showPdfCompare = false;
  DirectionsRoute? _route;
  var _loadingRoute = false;

  List<GpsPoint>? _adjustBaseBoundary;
  List<GpsPoint> _adjustDisplayBoundary = [];
  int? _selectedAdjustCorner;
  int? _lockedCorner1Index;
  LatLng? _lockedCorner1Pos;
  int? _lockedCorner2Index;
  LatLng? _lockedCorner2Pos;
  int _adjustLockedCount = 0;
  RigidBoundaryTransform? _adjustTransform;

  _AdjustFocus _adjustFocus = _AdjustFocus.pdfOverlay;
  var _pdfOverlayLocked = false;
  var _boundaryRetracedAfterPdfLock = false;
  var _pdfRetraceMode = false;
  ImageBounds? _pdfOverlayBase;
  ImageBounds? _pdfOverlayWorking;
  var _pdfNudgeMeters = 1.0;
  var _pdfScaleStepPct = 1.0;
  var _pdfRotateStepDeg = 0.5;
  List<int>? _retraceMapBytes;

  var _cornerNudgeMeters = 1.0;
  var _loadingAlignmentRestart = false;
  var _mapLayersDrawerOpen = false;
  var _basemap = MissionMapBasemap.hybrid;
  var _showBasemap = true;
  var _showBoundaryLayer = true;
  var _showRouteLayer = true;
  var _showStartMarkerLayer = true;
  Future<void> Function()? _adjustFitCamera;

  late AnimationController _boundaryController;

  LayoutGeorefApiService get _api => ref.read(layoutGeorefApiProvider);
  LocalMissionImportService get _localImport => ref.read(localMissionImportProvider);
  MissionLocalFirstService get _local => ref.read(missionLocalFirstProvider);

  List<MapRegionMarker> get _allRegions => regionsFromIntelligence(_intelligence?.raw);

  List<MapRegionMarker> get _visibleRegions {
    if (!_showRegionPins) return [];
    final all = _allRegions;
    return [
      for (var i = 0; i < all.length; i++)
        MapRegionMarker(
          id: all[i].id,
          point: all[i].point,
          visible: i < _regionsVisible,
        ),
    ];
  }

  Widget _wizardLayersDrawer(BuildContext context) {
    return MissionMapLayersDrawer(
      expanded: _mapLayersDrawerOpen,
      onToggle: () => setState(() => _mapLayersDrawerOpen = !_mapLayersDrawerOpen),
      maxPanelHeight: missionMapHudMaxPanelHeight(context, bottomReserved: _hudBottomReserved(context)),
      showOfficialMap: _showMapPdfOverlay,
      showRegionPins: _showRegionPins,
      showBoundary: _showBoundaryLayer,
      showRoute: _showRouteLayer,
      showStartMarker: _showStartMarkerLayer,
      showDraftBuildings: false,
      showWalkPath: false,
      showBasemap: _showBasemap,
      officialMapOpacity: _opacity,
      basemap: _basemap,
      onOfficialMapChanged: (v) => setState(() => _showMapPdfOverlay = v),
      onRegionPinsChanged: (v) => setState(() => _showRegionPins = v),
      onBoundaryChanged: (v) => setState(() => _showBoundaryLayer = v),
      onRouteChanged: (v) => setState(() => _showRouteLayer = v),
      onStartMarkerChanged: (v) => setState(() => _showStartMarkerLayer = v),
      onDraftBuildingsChanged: (_) {},
      onWalkPathChanged: (_) {},
      onBasemapVisibilityChanged: (v) => setState(() => _showBasemap = v),
      onOpacityChanged: (v) => setState(() => _opacity = v),
      onBasemapChanged: (v) => setState(() => _basemap = v),
    );
  }

  double _hudBottomReserved(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    var reserved = 0.0;
    if (_phase == _WizardPhase.mapExperience && _showReviewSheet) {
      reserved += h * 0.32;
    } else if (_phase == _WizardPhase.mapExperience &&
        _boundaryComplete &&
        AppConfig.hasGoogleMaps) {
      reserved += 88;
    } else if (_phase == _WizardPhase.adjust) {
      reserved += _pdfOverlayLocked && _adjustFocus == _AdjustFocus.boundary ? 132 : 220;
    }
    return reserved;
  }

  String _hlbDisplayCode() {
    final query = EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);
    final code = ref.watch(discoveryStatusProvider(query)).valueOrNull?.ebCode;
    if (code != null && code.isNotEmpty && code != kDefaultEbCode) return code;
    return kDefaultEbCode;
  }

  ImageBounds? get _adjustPdfBounds {
    if (_phase == _WizardPhase.adjust && _pdfOverlayWorking != null) {
      return _pdfOverlayWorking;
    }
    return _baseBounds ?? _imageBounds;
  }

  @override
  void initState() {
    super.initState();
    _boundaryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
    _boundaryController.addListener(() {
      setState(() => _boundaryProgress = _boundaryController.value);
    });
    _initGps();
    if (widget.restartAlignment) {
      _loadAlignmentRestart();
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _boundaryController.dispose();
    stopMissionGps();
    super.dispose();
  }

  Future<void> _initGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _mapCenter = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final fullScreenMap = (_phase == _WizardPhase.adjust ||
            (_phase == _WizardPhase.mapExperience && !_showReviewSheet) ||
            _phase == _WizardPhase.pdfEditor) &&
        _error == null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: fullScreenMap,
      appBar: fullScreenMap
          ? null
          : AppBar(
              title: Text(_titleForPhase()),
              backgroundColor: Colors.transparent,
              leading: _pdfRetraceMode
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to satellite',
                      onPressed: () => setState(() {
                        _pdfRetraceMode = false;
                        _phase = _WizardPhase.adjust;
                      }),
                    )
                  : null,
              actions: [
                if (_layoutImageUrl != null && _phase != _WizardPhase.upload)
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'View Official HLO Map',
                    onPressed: () => setState(() => _showPdfCompare = true),
                  ),
              ],
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loadingAlignmentRestart)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
          else if (_phase == _WizardPhase.mapExperience || _phase == _WizardPhase.adjust)
            _satelliteBody()
          else
            switch (_phase) {
              _WizardPhase.upload => _uploadBody(),
              _WizardPhase.analyzing => _analyzingBody(),
              _WizardPhase.pdfEditor => _pdfEditorBody(),
              _WizardPhase.verifyLandmarks => _verifyLandmarksBody(),
              _ => const SizedBox.shrink(),
            },
          if (_showPdfCompare) _pdfCompareOverlay(),
          if (_phase == _WizardPhase.mapExperience && _showReviewSheet) _reviewBottomSheet(),
        ],
      ),
    );
  }

  String _titleForPhase() {
    return switch (_phase) {
      _WizardPhase.upload => 'Import Official Mission',
      _WizardPhase.analyzing => 'Preparing satellite…',
      _WizardPhase.pdfEditor => _pdfRetraceMode ? 'Redraw boundary' : 'Georeference HLO Map',
      _WizardPhase.verifyLandmarks => 'Verify Landmarks',
      _WizardPhase.mapExperience => 'Your HLB Area',
      _WizardPhase.adjust => 'Adjust Alignment',
    };
  }

  void _exitAdjust() {
    setState(() => _phase = _WizardPhase.mapExperience);
  }

  Future<void> _loadAlignmentRestart() async {
    setState(() {
      _loadingAlignmentRestart = true;
      _error = null;
    });

    try {
      final session = await _localImport.loadAlignmentRestart(widget.ebId);
      if (session == null) {
        throw Exception('Saved HLO map not found — import the PDF again');
      }

      if (!mounted) return;
      setState(() {
        _layoutImageUrl = session.layoutImagePath;
        _boundaryRing = session.uvRing;
        _pins = session.pins;
        _manualDraft = ManualUploadDraft(
          mapBytes: session.mapBytes,
          layoutPath: session.layoutImagePath,
          mapFilePath: session.layoutImagePath,
          seed: session.seed,
        );
        _mapCenter = LatLng(session.seed.lat, session.seed.lng);
        _placementNotice = session.seed.warning;
        _phase = _WizardPhase.pdfEditor;
        _loadingAlignmentRestart = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAlignmentRestart = false;
        _error = e.toString().replaceFirst('Exception: ', '');
        _phase = _WizardPhase.upload;
      });
    }
  }

  Widget _uploadBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Import Official HLO Mission', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Upload the official HLO PDF. The white boundary is traced automatically — then place numbered pins and match each to Google Maps.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickPdfOrImage,
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose HLO PDF'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF42A5F5),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: kIsWeb ? null : _pickCamera,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(kIsWeb ? 'Camera not available on web' : 'Photograph printed map'),
          ),
        ],
      ),
    );
  }

  Widget _analyzingBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E676)),
            const SizedBox(height: 28),
            const Text('Preparing your area', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              _error ?? _analysisSteps[_analysisStep.clamp(0, _analysisSteps.length - 1)],
              style: TextStyle(color: _error != null ? Colors.orange : AppTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () => setState(() => _phase = _WizardPhase.upload), child: const Text('Try Again')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _satelliteBody() {
    if (_phase == _WizardPhase.adjust) {
      return _adjustBody();
    }

    final gps = position;
    final userLatLng = gps != null ? LatLng(gps.latitude, gps.longitude) : null;
    final center = MissionSatelliteMap.boundsCenter(_intelligence?.gpsBoundary ?? []) ??
        _mapCenter ??
        userLatLng ??
        const LatLng(10, 76);
    final boundary = _intelligence?.gpsBoundary ?? [];
    final navDest = _boundaryComplete && boundary.isNotEmpty ? missionEntryPoint(boundary) : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        MissionMapCanvas(
          center: center,
          boundary: boundary,
          regions: _visibleRegions,
          boundaryDrawProgress: _boundaryProgress,
          mode: MissionMapMode.prediction,
          showPdfOverlay: _showMapPdfOverlay && _layoutImageUrl != null && _imageBounds != null,
          pdfImageUrl: _layoutImageUrl,
          pdfBounds: _imageBounds,
          pdfOpacity: _opacity,
          showRegionPins: _showRegionPins,
          showBoundary: _showBoundaryLayer,
          showNavigationRoute: _showRouteLayer,
          showStartMarker: _showStartMarkerLayer,
          showBasemap: _showBasemap,
          mapType: _basemap.googleType,
          userPosition: userLatLng,
          navigationDestination: navDest,
          onRouteLoaded: (route) => setState(() {
            _route = route;
            _loadingRoute = false;
          }),
        ),
        MissionMapLayersDismissBarrier(
          visible: _mapLayersDrawerOpen,
          onDismiss: () => setState(() => _mapLayersDrawerOpen = false),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: _hudBottomReserved(context)),
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  right: 96,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: MissionMapHudStatus(
                      title: _boundaryComplete ? 'HLB on satellite' : 'Drawing boundary…',
                      subtitle: _boundaryComplete
                          ? 'Official map overlay · red dotted boundary'
                          : 'Tracing your HLB border',
                      icon: _boundaryComplete ? Icons.check_circle_outline : Icons.pentagon_outlined,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _wizardLayersDrawer(context),
                ),
              ],
            ),
          ),
        ),
        if (_boundaryComplete && AppConfig.hasGoogleMaps)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MissionNavigationBanner(route: _route, loading: _loadingRoute),
          ),
      ],
    );
  }

  Widget _adjustBody() {
    if (!AppConfig.hasGoogleMaps) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Corner alignment requires Google Maps. Add GOOGLE_MAPS_API_KEY to local.properties.',
            style: TextStyle(color: Colors.orange.shade200),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final pdfAdjusting = !_pdfOverlayLocked && _adjustFocus == _AdjustFocus.pdfOverlay;
    final boundaryAdjusting = _pdfOverlayLocked && _adjustFocus == _AdjustFocus.boundary;
    final needsRetrace = _pdfOverlayLocked && _pdfOverlayModified && !_boundaryRetracedAfterPdfLock;

    final canLockCorner = boundaryAdjusting &&
        _selectedAdjustCorner != null &&
        _adjustLockedCount < 2;
    final canSave = _pdfOverlayLocked &&
        (!_pdfOverlayModified || _boundaryRetracedAfterPdfLock) &&
        _adjustLockedCount >= 2;
    final canNudgeCorner = boundaryAdjusting &&
        _selectedAdjustCorner != null &&
        _adjustLockedCount < 2 &&
        _selectedAdjustCorner != _lockedCorner1Index &&
        _selectedAdjustCorner != _lockedCorner2Index;

    return Stack(
      fit: StackFit.expand,
      children: [
        BoundaryCornerAdjustMap(
          boundary: _adjustDisplayBoundary,
          selectedCornerIndex: boundaryAdjusting ? _selectedAdjustCorner : null,
          lockedCorner1Index: _lockedCorner1Index,
          lockedCorner2Index: _lockedCorner2Index,
          lockedCount: _adjustLockedCount,
          regions: _allRegions,
          showRegionPins: _showRegionPins,
          showPdfOverlay: _showMapPdfOverlay,
          pdfImageUrl: _layoutImageUrl,
          pdfBounds: _adjustPdfBounds,
          pdfOpacity: _opacity,
          enableCornerDrag: false,
          onMapReady: (fit) => _adjustFitCamera = fit,
          onCornerSelected: boundaryAdjusting ? _selectAdjustCorner : (_) {},
          onCornerDragged: boundaryAdjusting ? _previewAdjustCorner : (_, __) {},
        ),
        MissionMapLayersDismissBarrier(
          visible: _mapLayersDrawerOpen,
          onDismiss: () => setState(() => _mapLayersDrawerOpen = false),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: _hudBottomReserved(context)),
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: MissionMapHudStatus(
                      title: 'Align PDF & boundary',
                      subtitle: _adjustInstruction,
                      icon: Icons.open_with,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _wizardLayersDrawer(context),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => _adjustFitCamera?.call(),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.center_focus_strong, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: pdfAdjusting ? 220 : 132,
                  child: _mapLayerToggles(maxWidth: 200),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MissionMapNudgePad(
                        enabled: pdfAdjusting ? true : canNudgeCorner,
                        cornerLabel: pdfAdjusting
                            ? 'Move PDF'
                            : (canNudgeCorner
                                ? 'Corner ${(_selectedAdjustCorner ?? 0) + 1}'
                                : 'Select corner'),
                        stepMeters: pdfAdjusting ? _pdfNudgeMeters : _cornerNudgeMeters,
                        onStepChanged: (m) => setState(() {
                          if (pdfAdjusting) {
                            _pdfNudgeMeters = m;
                          } else {
                            _cornerNudgeMeters = m;
                          }
                        }),
                        onNudge: pdfAdjusting ? _nudgePdfOverlay : _nudgeSelectedCorner,
                      ),
                      if (pdfAdjusting) ...[
                        const SizedBox(height: 8),
                        MissionMapPdfAdjustControls(
                          enabled: true,
                          scaleStepPct: _pdfScaleStepPct,
                          rotateStepDeg: _pdfRotateStepDeg,
                          onScaleStepChanged: (v) => setState(() => _pdfScaleStepPct = v),
                          onRotateStepChanged: (v) => setState(() => _pdfRotateStepDeg = v),
                          onScaleDown: () => _scalePdfOverlay(up: false),
                          onScaleUp: () => _scalePdfOverlay(up: true),
                          onRotateLeft: () => _rotatePdfOverlay(left: true),
                          onRotateRight: () => _rotatePdfOverlay(left: false),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MissionMapHudPanel(
                        maxWidth: 168,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _adjustFocusChip(
                              label: 'PDF',
                              selected: _adjustFocus == _AdjustFocus.pdfOverlay,
                              enabled: !_pdfOverlayLocked,
                              onTap: () => setState(() => _adjustFocus = _AdjustFocus.pdfOverlay),
                            ),
                            const SizedBox(width: 6),
                            _adjustFocusChip(
                              label: 'Boundary',
                              selected: _adjustFocus == _AdjustFocus.boundary,
                              enabled: _pdfOverlayLocked &&
                                  (!_pdfOverlayModified || _boundaryRetracedAfterPdfLock),
                              onTap: () => setState(() => _adjustFocus = _AdjustFocus.boundary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      MissionMapHudPanel(
                        maxWidth: 168,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _pdfOverlayLocked ? Icons.lock : Icons.picture_as_pdf_outlined,
                              size: 16,
                              color: _pdfOverlayLocked ? const Color(0xFF42A5F5) : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _pdfOverlayLocked ? 'PDF locked' : 'PDF unlocked',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      if (boundaryAdjusting) ...[
                        const SizedBox(height: 8),
                        MissionMapHudPanel(
                          maxWidth: 140,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _adjustLockedCount >= 2 ? Icons.check_circle : Icons.lock_outline,
                                size: 16,
                                color: _adjustLockedCount >= 2 ? const Color(0xFF00E676) : Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_adjustLockedCount}/2 locked',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      MissionMapHudAction(
                        icon: Icons.close,
                        label: 'Back',
                        color: const Color(0xFF37474F),
                        onPressed: _exitAdjust,
                      ),
                      if (!_pdfOverlayLocked) ...[
                        const SizedBox(height: 6),
                        MissionMapHudAction(
                          icon: Icons.lock_outline,
                          label: 'Lock PDF',
                          color: const Color(0xFF42A5F5),
                          onPressed: _pdfOverlayWorking == null ? null : _lockPdfOverlay,
                        ),
                      ],
                      if (needsRetrace) ...[
                        const SizedBox(height: 6),
                        MissionMapHudAction(
                          icon: Icons.border_outer,
                          label: 'Retrace boundary',
                          color: const Color(0xFFFFA726),
                          onPressed: _enterBoundaryRetrace,
                        ),
                      ],
                      if (canLockCorner) ...[
                        const SizedBox(height: 6),
                        MissionMapHudAction(
                          icon: Icons.lock_outline,
                          label: 'Lock ${_selectedAdjustCorner! + 1}',
                          onPressed: _lockAdjustCorner,
                        ),
                      ],
                      if (canSave) ...[
                        const SizedBox(height: 6),
                        MissionMapHudAction(
                          icon: Icons.save_outlined,
                          label: 'Done',
                          color: const Color(0xFF00E676),
                          onPressed: _saveAdjustAndReview,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _adjustFocusChip({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? const Color(0xFF42A5F5).withValues(alpha: 0.35)
          : (enabled ? const Color(0xFF1A1A28) : Colors.white10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }

  String get _adjustInstruction {
    if (!_pdfOverlayLocked) {
      return 'Step 1: nudge, scale, and rotate the PDF overlay. Lock PDF when it matches satellite.';
    }
    if (_pdfOverlayModified && !_boundaryRetracedAfterPdfLock) {
      return 'PDF moved — retrace the white boundary on the map so the GPS ring matches.';
    }
    if (_adjustFocus == _AdjustFocus.pdfOverlay) {
      return 'PDF locked. Switch to Boundary to fine-tune corner positions.';
    }
    return switch (_adjustLockedCount) {
      0 => 'Tap a blue corner, nudge with arrows, then Lock. Whole boundary moves — shape unchanged.',
      1 => 'Corner ${_lockedCorner1Index! + 1} locked. Select another corner, nudge, then Lock to rotate.',
      _ => 'Both corners locked — tap Done.',
    };
  }

  bool get _pdfOverlayModified {
    final base = _pdfOverlayBase;
    final work = _pdfOverlayWorking;
    if (base == null || work == null) return false;
    const eps = 1e-9;
    return (base.north - work.north).abs() > eps ||
        (base.south - work.south).abs() > eps ||
        (base.east - work.east).abs() > eps ||
        (base.west - work.west).abs() > eps ||
        (base.rotation - work.rotation).abs() > 0.01;
  }

  void _initPdfOverlayForAdjust() {
    final base = _baseBounds ?? _imageBounds;
    _pdfOverlayBase = base;
    _pdfOverlayWorking = base;
    _pdfOverlayLocked = false;
    _boundaryRetracedAfterPdfLock = false;
    _pdfRetraceMode = false;
    _retraceMapBytes = null;
    _adjustFocus = _AdjustFocus.pdfOverlay;
    _pdfNudgeMeters = 1.0;
  }

  void _lockPdfOverlay() {
    if (_pdfOverlayWorking == null) return;
    setState(() {
      _pdfOverlayLocked = true;
      if (!_pdfOverlayModified) {
        _boundaryRetracedAfterPdfLock = true;
        _adjustFocus = _AdjustFocus.boundary;
      }
    });
    if (!_pdfOverlayModified && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF locked — adjust boundary corners if needed')),
      );
    }
  }

  void _nudgePdfOverlay(MapNudgeDirection direction) {
    if (_pdfOverlayLocked || _pdfOverlayWorking == null) return;
    final (dNorth, dEast) = switch (direction) {
      MapNudgeDirection.north => (_pdfNudgeMeters, 0.0),
      MapNudgeDirection.south => (-_pdfNudgeMeters, 0.0),
      MapNudgeDirection.east => (0.0, _pdfNudgeMeters),
      MapNudgeDirection.west => (0.0, -_pdfNudgeMeters),
    };
    setState(() {
      _pdfOverlayWorking = SatelliteAlignMath.shiftBounds(_pdfOverlayWorking!, dNorth, dEast);
    });
  }

  void _scalePdfOverlay({required bool up}) {
    if (_pdfOverlayLocked || _pdfOverlayWorking == null) return;
    final delta = _pdfScaleStepPct / 100;
    final factor = up ? 1 + delta : 1 - delta;
    if (factor <= 0.05) return;
    setState(() {
      _pdfOverlayWorking = SatelliteAlignMath.scaleBounds(_pdfOverlayWorking!, factor);
    });
  }

  void _rotatePdfOverlay({required bool left}) {
    if (_pdfOverlayLocked || _pdfOverlayWorking == null) return;
    final delta = (left ? -1 : 1) * _pdfRotateStepDeg;
    setState(() {
      _pdfOverlayWorking = SatelliteAlignMath.rotateBounds(_pdfOverlayWorking!, delta);
    });
  }

  List<({double x, double y})> _uvRingFromIntelligence() {
    final raw = _intelligence?.raw;
    final boundary = raw?['boundary'] as Map?;
    final uv = boundary?['uvRing'] as List?;
    if (uv == null) return [];
    return [
      for (final p in uv)
        if (p is Map<String, dynamic> || p is Map)
          (
            x: ((p as Map)['x'] as num).toDouble(),
            y: (p['y'] as num).toDouble(),
          ),
    ];
  }

  Future<void> _enterBoundaryRetrace() async {
    final path = _layoutImageUrl;
    if (path == null || _pdfOverlayWorking == null) return;

    try {
      final bytes = await readMissionLayoutBytes(path);
      if (bytes == null) throw Exception('Could not load layout image');
      if (!mounted) return;
      setState(() {
        _retraceMapBytes = bytes;
        _boundaryRing = _uvRingFromIntelligence();
        _pdfRetraceMode = true;
        _phase = _WizardPhase.pdfEditor;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _trackBoundaryRetrace() async {
    List<int>? bytes = _retraceMapBytes;
    if (bytes == null && _layoutImageUrl != null) {
      final loaded = await readMissionLayoutBytes(_layoutImageUrl!);
      bytes = loaded;
    }
    if (bytes == null) return;

    setState(() {
      _trackingBoundary = true;
      _error = null;
    });

    try {
      final ring = await _localImport.trackBoundary(Uint8List.fromList(bytes));
      if (!mounted) return;
      setState(() => _boundaryRing = ring);
      Future<void>.delayed(const Duration(milliseconds: 3000), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Boundary traced — apply to update the GPS ring')),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _trackingBoundary = false);
    }
  }

  void _completeBoundaryRetrace() {
    final bounds = _pdfOverlayWorking;
    if (bounds == null || _boundaryRing.length < 3) return;

    final gpsRing = SatelliteAlignMath.gpsBoundaryFromUvRing(bounds, _boundaryRing);
    if (gpsRing.length < 3) return;

    setState(() {
      _adjustBaseBoundary = gpsRing;
      _adjustDisplayBoundary = List.from(gpsRing);
      _lockedCorner1Index = null;
      _lockedCorner1Pos = null;
      _lockedCorner2Index = null;
      _lockedCorner2Pos = null;
      _adjustLockedCount = 0;
      _adjustTransform = null;
      _boundaryRetracedAfterPdfLock = true;
      _pdfRetraceMode = false;
      _adjustFocus = _AdjustFocus.boundary;
      _selectedAdjustCorner = _firstUnlockedCornerIndex();
      _phase = _WizardPhase.adjust;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Boundary redrawn on locked PDF — fine-tune corners if needed'),
        backgroundColor: Color(0xFF00E676),
      ),
    );
  }

  int? _firstUnlockedCornerIndex() {
    for (var i = 0; i < _adjustDisplayBoundary.length; i++) {
      if (i != _lockedCorner1Index && i != _lockedCorner2Index) return i;
    }
    return null;
  }

  void _nudgeSelectedCorner(MapNudgeDirection direction) {
    final index = _selectedAdjustCorner;
    if (index == null || _adjustLockedCount >= 2) return;
    if (index == _lockedCorner1Index || index == _lockedCorner2Index) return;
    if (index >= _adjustDisplayBoundary.length) return;

    final current = LatLng(_adjustDisplayBoundary[index].lat, _adjustDisplayBoundary[index].lng);
    final next = nudgeLatLng(current, direction, _cornerNudgeMeters);
    _previewAdjustCorner(index, next);
  }

  void _beginAdjust() {
    final base = _intelligence?.gpsBoundary ?? [];
    if (base.length < 3) return;
    setState(() {
      _phase = _WizardPhase.adjust;
      _showReviewSheet = false;
      _adjustBaseBoundary = base.map((p) => GpsPoint(p.lat, p.lng)).toList();
      _adjustDisplayBoundary = List.from(_adjustBaseBoundary!);
      _lockedCorner1Index = null;
      _lockedCorner1Pos = null;
      _lockedCorner2Index = null;
      _lockedCorner2Pos = null;
      _adjustLockedCount = 0;
      _adjustTransform = null;
      _selectedAdjustCorner = _firstUnlockedCornerIndex();
      _initPdfOverlayForAdjust();
    });
  }

  void _selectAdjustCorner(int index) {
    if (_adjustLockedCount >= 2) return;
    if (index == _lockedCorner1Index || index == _lockedCorner2Index) return;
    setState(() => _selectedAdjustCorner = index);
  }

  void _previewAdjustCorner(int index, LatLng position) {
    final base = _adjustBaseBoundary;
    if (base == null || base.isEmpty) return;

    setState(() {
      _selectedAdjustCorner = index;
      if (_adjustLockedCount == 0) {
        _adjustDisplayBoundary = BoundaryRigidAlignMath.translate(base, index, position);
      } else if (_adjustLockedCount == 1 && _lockedCorner1Pos != null) {
        final afterTranslate = BoundaryRigidAlignMath.translate(
          base,
          _lockedCorner1Index!,
          _lockedCorner1Pos!,
        );
        _adjustDisplayBoundary = BoundaryRigidAlignMath.rotateAround(
          afterTranslate,
          _lockedCorner1Pos!,
          index,
          position,
        );
      }
    });
  }

  void _lockAdjustCorner() {
    final index = _selectedAdjustCorner;
    final base = _adjustBaseBoundary;
    if (index == null || base == null || _adjustDisplayBoundary.isEmpty) return;

    final pos = LatLng(
      _adjustDisplayBoundary[index].lat,
      _adjustDisplayBoundary[index].lng,
    );

    setState(() {
      if (_adjustLockedCount == 0) {
        _lockedCorner1Index = index;
        _lockedCorner1Pos = pos;
        _adjustLockedCount = 1;
        _adjustDisplayBoundary = BoundaryRigidAlignMath.translate(base, index, pos);
        _adjustTransform = BoundaryRigidAlignMath.transformFromLocks(
          baseRing: base,
          corner1Index: index,
          corner1Target: pos,
        );
      } else if (_adjustLockedCount == 1 && _lockedCorner1Index != null && _lockedCorner1Pos != null) {
        _lockedCorner2Index = index;
        _lockedCorner2Pos = pos;
        _adjustLockedCount = 2;
        final afterTranslate = BoundaryRigidAlignMath.translate(
          base,
          _lockedCorner1Index!,
          _lockedCorner1Pos!,
        );
        _adjustDisplayBoundary = BoundaryRigidAlignMath.rotateAround(
          afterTranslate,
          _lockedCorner1Pos!,
          index,
          pos,
        );
        _adjustTransform = BoundaryRigidAlignMath.transformFromLocks(
          baseRing: base,
          corner1Index: _lockedCorner1Index!,
          corner1Target: _lockedCorner1Pos!,
          corner2Index: index,
          corner2Target: pos,
        );
      }
      _selectedAdjustCorner = _adjustLockedCount < 2 ? _firstUnlockedCornerIndex() : null;
    });
  }

  Widget _reviewBottomSheet() {
    final intel = _intelligence!;
    final confidence = intel.raw != null
        ? SpatialConfidenceScores.fromIntelligence(intel.raw!).overall
        : intel.alignmentQualityPercent;
    final ebCode = _hlbDisplayCode();

    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.24,
      maxChildSize: 0.55,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF14141E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, -3))],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                ebCode == kDefaultEbCode ? 'Your HLB map' : 'HLB $ebCode',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Text('Mission Review', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _ReviewStat('Landmarks', '${intel.summary.possibleLandmarks}')),
                  Expanded(child: _ReviewStat('Confidence', '$confidence%')),
                ],
              ),
              if (_placementNotice != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2A24),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    _placementNotice!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Hypotheses only — validate on your walk.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _looksCorrect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('LOOKS CORRECT', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pdfCompareOverlay() {
    final center = _mapCenter ?? const LatLng(10, 76);
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Expanded(child: Text('Official HLO vs Live Satellite', style: TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showPdfCompare = false)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Official map', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        Expanded(
                          child: _layoutImageUrl != null
                              ? MissionLayoutImage(ref: _layoutImageUrl!, fit: BoxFit.contain)
                              : const Center(child: Text('No preview')),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Live satellite', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        Expanded(
                          child: MissionMapCanvas(
                            center: center,
                            boundary: _intelligence?.gpsBoundary ?? [],
                            regions: _allRegions,
                            boundaryDrawProgress: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapLayerToggles({double maxWidth = 240}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('PDF overlay'),
                    selected: _showMapPdfOverlay,
                    onSelected: (v) => setState(() => _showMapPdfOverlay = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (_showMapPdfOverlay) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Text('PDF opacity', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    Expanded(
                      child: Slider(
                        value: _opacity,
                        min: 0.05,
                        max: 0.95,
                        onChanged: (v) => setState(() => _opacity = v),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _adjustControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: const Color(0xFF1A1A2E),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _mapLayerToggles(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _adjustLockedCount >= 2 ? Icons.check_circle : Icons.pin_drop_outlined,
                size: 16,
                color: _adjustLockedCount >= 2 ? const Color(0xFF00E676) : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _adjustLockedCount >= 2
                      ? 'Alignment complete'
                      : 'Locked ${_adjustLockedCount}/2 corners',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Red dotted line = HLB boundary · Blue = corner · Orange = selected · Green = locked.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  void _startAnalysisAnimation() {
    _analysisStep = 0;
    _analysisTimer?.cancel();
    _analysisTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (!mounted || _phase != _WizardPhase.analyzing) {
        t.cancel();
        return;
      }
      setState(() => _analysisStep = (_analysisStep + 1).clamp(0, _analysisSteps.length - 1));
    });
  }

  Future<void> _startMapReveal() async {
    setState(() {
      _phase = _WizardPhase.mapExperience;
      _boundaryProgress = 0;
      _regionsVisible = 0;
      _boundaryComplete = false;
      _showReviewSheet = false;
      _route = null;
      _loadingRoute = AppConfig.hasGoogleMaps;
    });

    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (_) => setState(() {}),
      onBreadcrumb: (_) {},
    );

    await _boundaryController.forward(from: 0);
    if (!mounted) return;
    setState(() => _boundaryComplete = true);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _showReviewSheet = true;
        _mapLayersDrawerOpen = false;
      });
      final notice = _placementNotice;
      if (notice != null && notice.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notice), duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  Future<void> _pickPdfOrImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      await _uploadAndAnalyze(mapBytes: bytes, mapFileName: picked.name);
      return;
    }
    if (picked.path == null) return;
    await _uploadAndAnalyze(mapFile: File(picked.path!));
  }

  Future<void> _pickCamera() async {
    if (kIsWeb) return;
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img == null) return;
    await _uploadAndAnalyze(mapFile: File(img.path));
  }

  Widget _pdfEditorBody() {
    if (_layoutImageUrl == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E676)),
            const SizedBox(height: 16),
            Text(
              _preparingPdf
                  ? 'Rendering PDF… large maps can take up to a minute on web'
                  : 'Loading map…',
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_pdfRetraceMode && _manualDraft == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E676)),
            const SizedBox(height: 16),
            Text(
              _preparingPdf
                  ? 'Rendering PDF… large maps can take up to a minute on web'
                  : 'Loading map…',
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final readyCount = _pins.where((p) => p.isReady).length;
    final canShow = _pdfRetraceMode
        ? _boundaryRing.length >= 3
        : _boundaryRing.length >= 3 && readyCount >= kMinGeorefMatchedPins;
    final draft = _manualDraft;
    final placesBias = draft != null
        ? LatLng(draft.seed.lat, draft.seed.lng)
        : (_mapCenter ?? const LatLng(10, 76));

    return HloPdfGeorefEditor(
      imagePath: _layoutImageUrl!,
      imageBytes: draft?.mapBytes,
      onBack: _pdfRetraceMode
          ? () => setState(() {
                _pdfRetraceMode = false;
                _phase = _WizardPhase.adjust;
              })
          : () => context.pop(),
      boundaryRing: _boundaryRing,
      pins: _pins,
      placesBias: placesBias,
      isTrackingBoundary: _trackingBoundary,
      canShowSatellite: canShow,
      retraceOnly: _pdfRetraceMode,
      onTrackBoundary: _pdfRetraceMode ? _trackBoundaryRetrace : _trackBoundary,
      onPinAdded: (pin) => setState(() => _pins = [..._pins, pin]),
      onPinUpdated: (pin) => setState(() {
        _pins = [
          for (final p in _pins)
            if (p.number == pin.number) pin else p,
        ];
      }),
      onPinRemoved: (number) => setState(() {
        final remaining = _pins.where((p) => p.number != number).toList();
        _pins = [
          for (var i = 0; i < remaining.length; i++)
            remaining[i].copyWith(number: i + 1),
        ];
      }),
      onShowSatellite: _pdfRetraceMode ? _completeBoundaryRetrace : _completeManualGeoref,
    );
  }

  Future<void> _trackBoundary() async {
    final draft = _manualDraft;
    if (draft == null) return;

    setState(() {
      _trackingBoundary = true;
      _error = null;
    });

    try {
      final ring = await _localImport.trackBoundary(draft.mapBytes, metadata: draft.metadata);
      if (!mounted) return;
      setState(() => _boundaryRing = ring);
      Future<void>.delayed(const Duration(milliseconds: 3000), () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Boundary traced — red line follows the white border')),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _trackingBoundary = false);
    }
  }

  Future<void> _completeManualGeoref() async {
    final draft = _manualDraft;
    if (draft == null) return;

    setState(() {
      _phase = _WizardPhase.analyzing;
      _analysisStep = 0;
      _error = null;
    });
    _startAnalysisAnimation();

    try {
      final controlPoints = _localImport.controlPointsFromPins(_pins);
      final args = ManualIntelIsolateArgs(
        mapBytes: draft.mapBytes,
        layoutPath: draft.layoutPath,
        uvRing: _boundaryRing,
        controlPoints: controlPoints.map((p) => p.toJson()).toList(),
      );
      final json = kIsWeb
          ? buildManualIntelInIsolate(args)
          : await compute(buildManualIntelInIsolate, args);
      final intel = MissionIntelligencePackage.fromJson(json);
      _analysisTimer?.cancel();
      _intelligence = intel;
      _imageBounds = intel.imageBounds;
      _baseBounds = intel.imageBounds;
      _mapCenter = MissionSatelliteMap.boundsCenter(intel.gpsBoundary) ??
          LatLng(controlPoints.first.lat, controlPoints.first.lng);
      _placementNotice =
          'HLB placed using ${controlPoints.length} pins (${intel.raw?['alignment']?['alignmentLabel'] ?? 'matched'}, '
          '${intel.raw?['alignment']?['rmsErrorMeters'] ?? '?'}m error).';
      await _startMapReveal();
    } catch (e) {
      _analysisTimer?.cancel();
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _phase = _WizardPhase.pdfEditor;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_error ?? 'Could not align map')),
        );
      }
    }
  }

  Widget _verifyLandmarksBody() {
    final draft = _importDraft!;
    final anchorService = LandmarkAnchorService();
    return LandmarkVerificationPanel(
      layoutImagePath: draft.layoutPath,
      rows: _landmarkRows,
      ocrLabelCount: draft.anchorPrep.ocrLabelCount,
      seed: draft.anchorPrep.seed,
      onSearchPlaces: (text) => anchorService.searchPlacesForLabel(
        labelText: text,
        locality: draft.anchorPrep.searchLocality,
        district: draft.anchorPrep.searchDistrict,
        seed: draft.anchorPrep.seed,
      ),
      onContinue: _completeImportWithLandmarks,
      onSkip: _completeImportWithSeedFallback,
    );
  }

  Future<Position> _resolveUploadPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return Position(
        latitude: 20.5937,
        longitude: 78.9629,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
  }

  Future<void> _uploadAndAnalyze({File? mapFile, Uint8List? mapBytes, String? mapFileName}) async {
    setState(() {
      _error = null;
      _placementNotice = null;
      _importDraft = null;
      _landmarkRows = [];
      _manualDraft = null;
      _boundaryRing = [];
      _pins = [];
    });

    if (AppConfig.standaloneMode) {
      setState(() {
        _phase = _WizardPhase.pdfEditor;
        _preparingPdf = true;
      });
    } else {
      setState(() => _phase = _WizardPhase.analyzing);
      _startAnalysisAnimation();
    }

    try {
      final pos = await _resolveUploadPosition();
      if (AppConfig.standaloneMode) {
        final manual = await _localImport.prepareManualUpload(
          ebId: widget.ebId,
          mapFile: mapFile,
          mapBytes: mapBytes,
          mapFileName: mapFileName,
          userLat: pos.latitude,
          userLng: pos.longitude,
        );
        if (manual.metadata?.ebNo != null) {
          await applyPdfEbCode(
            ref,
            projectId: widget.projectId,
            ebId: widget.ebId,
            ebCode: manual.metadata!.ebNo!,
          );
        }
        if (!mounted) return;
        setState(() {
          _manualDraft = manual;
          _layoutImageUrl = manual.layoutPath;
          _preparingPdf = false;
        });
        // Show the PDF editor immediately; trace boundary in the background.
        unawaited(_trackBoundary());
        return;
      }

      if (mapFile == null) {
        throw Exception('PDF upload is not supported without a file on this platform');
      }
      final seed = await MissionSeedLocationResolver().resolve(
        mapFile: mapFile,
        userLat: pos.latitude,
        userLng: pos.longitude,
      );
      final session = await _api.uploadLayout(widget.ebId, file: mapFile);
      _layoutImageUrl = session.layoutImageUrl;
      final intel = await _api.generateIntelligence(widget.ebId, seed.lat, seed.lng);
      _analysisTimer?.cancel();
      _intelligence = intel;
      _imageBounds = intel.imageBounds;
      _baseBounds = intel.imageBounds;
      _mapCenter = LatLng(seed.lat, seed.lng);
      _placementNotice = seed.warning;
      await _startMapReveal();
    } catch (e) {
      _analysisTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _preparingPdf = false;
        if (AppConfig.standaloneMode) _phase = _WizardPhase.upload;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error ?? 'Upload failed')),
      );
    }
  }

  Future<void> _completeImportWithLandmarks(List<LandmarkMatchRow> confirmed) async {
    final draft = _importDraft;
    if (draft == null) return;

    setState(() {
      _phase = _WizardPhase.analyzing;
      _analysisStep = 3;
      _error = null;
    });

    try {
      final controlPoints = _localImport.controlPointsFromMatches(confirmed);
      final intel = await _localImport.buildIntelligence(
        draft: draft,
        controlPoints: controlPoints,
      );
      _analysisTimer?.cancel();
      _intelligence = intel;
      _imageBounds = intel.imageBounds;
      _baseBounds = intel.imageBounds;
      _mapCenter = MissionSatelliteMap.boundsCenter(intel.gpsBoundary) ??
          LatLng(confirmed.first.selected!.location.latitude, confirmed.first.selected!.location.longitude);
      _placementNotice =
          'HLB placed using ${controlPoints.length} verified landmarks (${intel.raw?['alignment']?['alignmentLabel'] ?? 'matched'}, '
          '${intel.raw?['alignment']?['rmsErrorMeters'] ?? '?'}m error).';
      await _startMapReveal();
    } catch (e) {
      _analysisTimer?.cancel();
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _phase = _WizardPhase.verifyLandmarks;
      });
    }
  }

  Future<void> _completeImportWithSeedFallback() async {
    final draft = _importDraft;
    if (draft == null) return;

    setState(() {
      _phase = _WizardPhase.analyzing;
      _analysisStep = 3;
      _error = null;
    });

    try {
      final seed = draft.anchorPrep.seed;
      final intel = await _localImport.buildIntelligence(draft: draft, seedLocation: seed);
      _analysisTimer?.cancel();
      _intelligence = intel;
      _imageBounds = intel.imageBounds;
      _baseBounds = intel.imageBounds;
      _mapCenter = LatLng(seed.lat, seed.lng);
      _placementNotice = seed.warning ??
          (seed.source == MissionSeedSource.pdfMetadata
              ? 'HLB placed from official map: ${seed.geocodedAddress ?? seed.geocodeQuery}'
              : 'Could not verify landmarks — placed using PDF address or your location.');
      await _startMapReveal();
    } catch (e) {
      _analysisTimer?.cancel();
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _saveAdjustAndReview() async {
    if (!_pdfOverlayLocked) return;
    if (_pdfOverlayModified && !_boundaryRetracedAfterPdfLock) return;
    if (_adjustLockedCount < 2 || _adjustDisplayBoundary.length < 3) return;

    final transform = _adjustTransform;
    final intel = _intelligence;
    if (transform == null || intel == null) return;

    final newBoundary = _adjustDisplayBoundary;
    final newImageBounds = _pdfOverlayWorking ?? _baseBounds ?? _imageBounds;
    final raw = Map<String, dynamic>.from(intel.raw ?? {});
    final hypotheses = Map<String, dynamic>.from(raw['hypotheses'] as Map? ?? {});
    final targets = hypotheses['observationTargets'] as List<dynamic>? ?? [];

    final updatedTargets = <Map<String, dynamic>>[];
    for (final t in targets) {
      if (t is! Map<String, dynamic>) continue;
      final m = Map<String, dynamic>.from(t);
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        final moved = BoundaryRigidAlignMath.applyTransform(GpsPoint(lat, lng), transform);
        m['lat'] = moved.lat;
        m['lng'] = moved.lng;
      }
      updatedTargets.add(m);
    }

    hypotheses['observationTargets'] = updatedTargets;
    raw['hypotheses'] = hypotheses;
    raw['boundary'] = {
      ...(raw['boundary'] as Map<String, dynamic>? ?? {}),
      'gpsRing': newBoundary.map((p) => p.toJson()).toList(),
      if (_boundaryRetracedAfterPdfLock && _boundaryRing.length >= 3)
        'uvRing': _boundaryRing.map((p) => {'x': p.x, 'y': p.y}).toList(),
    };

    if (newImageBounds != null) {
      raw['imageBounds'] = newImageBounds.toJson();
      final alignment = Map<String, dynamic>.from(raw['alignment'] as Map? ?? {});
      alignment['imageBounds'] = newImageBounds.toJson();
      raw['alignment'] = alignment;
    }

    final updatedIntel = MissionIntelligencePackage.fromJson(raw);

    if (AppConfig.standaloneMode) {
      await _localImport.saveGpsBoundary(widget.ebId, newBoundary);
    } else if (intel.gpsBoundary.isNotEmpty) {
      await _api.saveGpsBoundary(widget.ebId, newBoundary);
    }

    setState(() {
      _intelligence = updatedIntel;
      if (newImageBounds != null) {
        _imageBounds = newImageBounds;
        _baseBounds = newImageBounds;
      }
      _phase = _WizardPhase.mapExperience;
      _boundaryProgress = 1;
      _boundaryComplete = true;
      _regionsVisible = _allRegions.length;
      _showReviewSheet = true;
      _mapLayersDrawerOpen = false;
      _placementNotice = _pdfOverlayModified
          ? 'PDF overlay and boundary aligned on satellite.'
          : 'Boundary nudged using 2 locked corners — shape unchanged.';
    });
  }

  Future<void> _looksCorrect() async {
    setState(() {
      _showReviewSheet = false;
      _phase = _WizardPhase.analyzing;
      _error = null;
      _analysisStep = 3;
    });

    try {
      if (AppConfig.standaloneMode) {
        final state = await _local.getRawState(widget.ebId);
        final raw = _intelligence?.raw;
        if (raw == null || _intelligence!.gpsBoundary.length < 3) {
          throw Exception('Mission intelligence not ready');
        }
        final pdfCode = _manualDraft?.metadata?.ebNo?.trim();
        final ebCode = (pdfCode != null && pdfCode.isNotEmpty)
            ? pdfCode
            : (state?.ebCode ?? kDefaultEbCode);
        if (pdfCode != null && pdfCode.isNotEmpty) {
          await applyPdfEbCode(
            ref,
            projectId: widget.projectId,
            ebId: widget.ebId,
            ebCode: pdfCode,
          );
        }
        await _localImport.finalizeMission(
          ebId: widget.ebId,
          ebCode: ebCode,
          intelligence: raw,
          gpsBoundary: _intelligence!.gpsBoundary,
        );
        await ref.read(localRegistryProvider).updateEbStatus(
              widget.projectId,
              widget.ebId,
              status: 'published',
            );
      } else {
        await _api.confirmIntelligence(widget.ebId);
        await _api.finalize(widget.ebId);
        if (_intelligence?.raw != null) {
          await _local.saveMissionIntelligence(widget.ebId, _intelligence!.raw!);
        }
        await _local.hydrateOfficialBoundary(widget.ebId);
      }
      ref.invalidate(discoveryStatusProvider(EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mission ready — your area is on the map'),
            backgroundColor: Color(0xFF00E676),
          ),
        );
        context.go('/mission/${widget.projectId}/eb/${widget.ebId}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _phase = _WizardPhase.mapExperience;
        _showReviewSheet = true;
        _mapLayersDrawerOpen = false;
      });
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF00E676)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ReviewStat extends StatelessWidget {
  const _ReviewStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      ),
    );
  }
}

// Re-use confidence parser from wizard
class SpatialConfidenceScores {
  SpatialConfidenceScores({
    required this.boundary,
    required this.structures,
    required this.roads,
    required this.landmarks,
    required this.overall,
  });

  final int boundary;
  final int structures;
  final int roads;
  final int landmarks;
  final int overall;

  factory SpatialConfidenceScores.fromIntelligence(Map<String, dynamic> raw) {
    final c = raw['confidence'] as Map<String, dynamic>? ?? {};
    int pct(dynamic v) => ((v as num?)?.toDouble() ?? 0.5 * 100).round().clamp(0, 100);
    if (c.containsKey('overall')) {
      return SpatialConfidenceScores(
        boundary: pct(c['boundary']),
        structures: pct(c['structures']),
        roads: pct(c['roads']),
        landmarks: pct(c['landmarks']),
        overall: pct(c['overall']),
      );
    }
    final alignment = raw['alignment'] as Map<String, dynamic>? ?? {};
    final o = alignment['qualityPercent'] as int? ?? 85;
    return SpatialConfidenceScores(boundary: o, structures: o, roads: o, landmarks: o, overall: o);
  }
}
