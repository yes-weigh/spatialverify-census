import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/l10n/app_locale_provider.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/maps/google_directions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hlb_geo_engine.dart';
import '../data/hlb_official_catalog.dart';
import '../data/hlb_map_pdf_exporter.dart';
import '../widgets/hlb_template_sheet_preview.dart';
import '../data/mission_map_session.dart';
import '../widgets/bearing_arrow.dart';
import '../widgets/mission_hlb_mark_sheet.dart';
import '../widgets/mission_line_feature_history.dart';
import '../widgets/mission_hlb_form_sheet_backdrop.dart';
import '../widgets/mission_map_canvas.dart';
import '../widgets/mission_map_game_hud.dart';
import '../widgets/mission_navigation_banner.dart';
import '../widgets/mission_satellite_map.dart';
import '../models/mission_models.dart';
import 'mission_providers.dart';

/// Full-screen gamified map — primary HLB enumerator experience.
class MissionGameMapScreen extends ConsumerStatefulWidget {
  const MissionGameMapScreen({
    required this.projectId,
    required this.ebId,
    this.initialPosition,
    super.key,
  });

  final String projectId;
  final String ebId;
  final Position? initialPosition;

  @override
  ConsumerState<MissionGameMapScreen> createState() => _MissionGameMapScreenState();
}

class _MissionGameMapScreenState extends ConsumerState<MissionGameMapScreen> with MissionGpsTracking {
  MissionMapSession? _session;
  DirectionsRoute? _route;
  var _loadingRoute = false;
  var _stepIndex = 0;
  var _navigateMode = false;
  var _layersOpen = false;
  var _fitToken = 0;

  var _showPdf = true;
  var _showPins = false;
  var _showBoundary = true;
  var _showRoute = false;
  var _showStartMarker = false;
  var _showDraftBuildings = true;
  var _showHlbLines = true;
  var _showWalkPath = true;
  var _showBasemap = true;
  var _pdfOpacity = 0.45;
  var _basemap = MissionMapBasemap.hybrid;
  var _exportingPdf = false;

  final _positionNotifier = ValueNotifier<Position?>(null);
  Timer? _aimCursorThrottle;
  DateTime? _lastAimCursorPaint;

  MissionHlbLandmarkPin? _fineTuningLandmark;
  gmaps.LatLng? _fineTunePosition;
  gmaps.LatLng? _fineTuneOriginal;

  var _lineDrawMode = false;
  var _placeTool = MapPlaceTool.building;
  String? _lineDraftSegmentType;
  gmaps.LatLng? _aimCursor;
  final List<gmaps.LatLng> _lineDraftPoints = [];
  Future<gmaps.LatLng> Function()? _readMapCenter;

  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      position = widget.initialPosition;
      _positionNotifier.value = widget.initialPosition;
    }
    _boot();
  }

  Future<void> _boot() async {
    await bootMissionGps(
      ebId: widget.ebId,
      rebuildOnGpsUpdate: false,
      onPosition: (pos) {
        _positionNotifier.value = pos;
        if (_navigateMode) {
          final prevStep = _stepIndex;
          _updateStepIndex();
          if (prevStep != _stepIndex && mounted) setState(() {});
        }
      },
      onBreadcrumb: (_) {},
    );
    await _reloadSession();
  }

  Future<void> _openGeorefWizard() async {
    await context.push('/mission/${widget.projectId}/eb/${widget.ebId}/georef');
    if (!mounted) return;
    ref.invalidate(discoveryStatusProvider(_query));
    await _reloadSession();
  }

  Future<void> _openFineTunePdf() async {
    await context.push('/mission/${widget.projectId}/eb/${widget.ebId}/fine-tune-pdf');
    if (!mounted) return;
    ref.invalidate(discoveryStatusProvider(_query));
    await _reloadSession();
  }

  Future<void> _reloadSession() async {
    final local = ref.read(missionLocalFirstProvider);
    final session = await loadMissionMapSession(local, widget.ebId);
    if (mounted) {
      setState(() {
        _session = session;
        if (session?.hasBoundary == true) {
          _showPdf = true;
          _showDraftBuildings = true;
          _showBasemap = true;
        }
        if ((session?.hlbBuildings.length ?? 0) > 0) {
          _showDraftBuildings = true;
          _showWalkPath = true;
        }
      });
    }
  }

  void _updateStepIndex() {
    final route = _route;
    final pos = position;
    if (route == null || pos == null || route.steps.isEmpty) return;

    var nearest = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < route.steps.length; i++) {
      final end = route.steps[i].endLocation;
      final d = HlbGeoEngine.haversineMeters(pos.latitude, pos.longitude, end.latitude, end.longitude);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    if (nearest != _stepIndex) _stepIndex = nearest;
  }

  @override
  void dispose() {
    _aimCursorThrottle?.cancel();
    _positionNotifier.dispose();
    stopMissionGps();
    super.dispose();
  }

  String _phaseLabel(DiscoveryStatus d) {
    final s = ref.read(appStringsProvider);
    if (_fineTuningLandmark != null) {
      return s.fineTuneLandmarkHint;
    }
    if (!d.hasOfficialBoundary) return s.importBoundaryHint;
    if (_lineDrawMode) {
      return s.traceRoadHint;
    }
    return s.crosshairHint;
  }

  ({String label, IconData icon, Color color, VoidCallback onTap}) _primaryAction(
    DiscoveryStatus d, {
    required BuildContext context,
  }) {
    final s = ref.read(appStringsProvider);
    if (!d.hasOfficialBoundary) {
      return (
        label: s.importHloPdf,
        icon: Icons.upload_file_outlined,
        color: const Color(0xFF00897B),
        onTap: _openGeorefWizard,
      );
    }
    if (_navigateMode) {
      return (
        label: s.stopNavigation,
        icon: Icons.close,
        color: const Color(0xFF546E7A),
        onTap: () => setState(() {
          _navigateMode = false;
          _route = null;
          _showRoute = false;
          _showStartMarker = false;
        }),
      );
    }
    return (
      label: s.openMapLayers,
      icon: Icons.layers_outlined,
      color: const Color(0xFF42A5F5),
      onTap: () => setState(() => _layersOpen = true),
    );
  }

  Future<void> _downloadHlbMapPdf() async {
    if (_exportingPdf) return;
    final s = ref.read(appStringsProvider);
    setState(() => _exportingPdf = true);
    try {
      final map = await ref.read(draftMapProvider(_query).future);
      final state = await ref.read(missionLocalFirstProvider).getRawState(widget.ebId);
      await shareHlbMapPdfFromState(
        map: map,
        layoutGeoref: state?.layoutGeoref,
        ebId: widget.ebId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.pdfExportFailed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  void _openMoreMenu(BuildContext context, DiscoveryStatus d) {
    setState(() => _layersOpen = false);
    final s = ref.read(appStringsProvider);
    showMissionMoreSheet(
      context,
      items: [
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.upload_file_outlined,
            label: s.reimportHloPdf,
            onTap: _openGeorefWizard,
          ),
        if (d.hasOfficialBoundary && AppConfig.hasGoogleMaps)
          MissionMoreSheetItem(
            icon: Icons.tune,
            label: s.fineTunePdfOverlay,
            onTap: _openFineTunePdf,
          ),
        if (d.hasOfficialBoundary && _session?.startPoint != null)
          MissionMoreSheetItem(
            icon: Icons.navigation_outlined,
            label: s.navigateToNwCorner,
            onTap: () => setState(() {
              _navigateMode = true;
              _loadingRoute = AppConfig.hasGoogleMaps;
              _showRoute = true;
              _showStartMarker = true;
            }),
          ),
        MissionMoreSheetItem(
          icon: Icons.map_outlined,
          label: s.hlbLayoutMap,
          onTap: () => _showDraftSheet(context),
        ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.download_outlined,
            label: s.downloadHlbMapPdf,
            onTap: _exportingPdf ? null : _downloadHlbMapPdf,
          ),
        if (d.buildingsDiscovered > 0)
          MissionMoreSheetItem(
            icon: Icons.home_work_outlined,
            label: s.houseListing,
            onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/listing'),
          ),
        MissionMoreSheetItem(
          icon: Icons.dashboard_outlined,
          label: s.dashboard,
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/dashboard'),
        ),
        MissionMoreSheetItem(
          icon: Icons.history,
          label: s.walkReplay,
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/replay'),
        ),
        MissionMoreSheetItem(
          icon: Icons.warning_amber_outlined,
          label: s.coverageGaps,
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/gaps'),
        ),
        MissionMoreSheetItem(
          icon: Icons.translate,
          label: s.switchLanguageLabel,
          onTap: () async {
            final target = ref.read(appLanguageProvider).toggleTarget;
            await ref.read(appLanguageProvider.notifier).setLanguage(target);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppStrings(target).languageChangedSnack(target))),
            );
          },
        ),
        MissionMoreSheetItem(
          icon: Icons.folder_outlined,
          label: s.projects,
          onTap: () => context.push('/projects'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final completionAsync = ref.watch(missionCompletionProvider(_query));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final session = _session;
          final boundary = session?.boundaryRing ?? [];
          final center = session?.mapCenter ??
              MissionSatelliteMap.boundsCenter(boundary) ??
              const LatLng(20.59, 78.96);
          final start = session?.startPoint;
          final showNav = _navigateMode && start != null && d.hasOfficialBoundary;
          final showAimCrosshair = d.hasOfficialBoundary && _fineTuningLandmark == null;
          final showPlaceHud = showAimCrosshair && !_lineDrawMode && !_navigateMode;
          final showLegacyBar = !showPlaceHud && !_lineDrawMode && _fineTuningLandmark == null;
          final showFineTune = _fineTuningLandmark != null;
          final navInset = showNav && AppConfig.hasGoogleMaps ? 72.0 : 0.0;
          const edgePad = 16.0;
          final bottomInset = navInset + edgePad;
          final bottomHudHeight = _lineDrawMode
              ? 148.0
              : showFineTune
                  ? 80.0
                  : showPlaceHud
                      ? 132.0
                      : showLegacyBar
                          ? 68.0
                          : 0.0;
          final hudBottomReserved = bottomInset + bottomHudHeight;
          final primary = _primaryAction(d, context: context);
          final showHlbFormSheet = !_showBasemap && !_showPdf && d.hasOfficialBoundary;

          Widget mapLayer(Position? livePos) {
            final userLatLng = livePos != null ? LatLng(livePos.latitude, livePos.longitude) : null;
            return RepaintBoundary(
              child: MissionMapCanvas(
                center: center,
                boundary: boundary,
                userPosition: userLatLng,
                mode: MissionMapMode.mission,
                showPdfOverlay: _showPdf && session?.layoutImagePath != null && session?.imageBounds != null,
                pdfImageUrl: session?.layoutImagePath,
                pdfBounds: session?.imageBounds,
                pdfOpacity: _pdfOpacity,
                boundaryUvRing: session?.uvRing ?? const [],
                showRegionPins: _showPins,
                showBoundary: _showBoundary && !showHlbFormSheet,
                showNavigationRoute: _showRoute && showNav,
                showStartMarker: _showStartMarker && start != null,
                draftPins: session?.draftPins ?? const [],
                showDraftPins: false,
                hlbBuildings: session?.hlbBuildings ?? const [],
                hlbLandmarks: session?.hlbLandmarks ?? const [],
                hlbLineFeatures: session?.hlbLineFeatures ?? const [],
                lineDraftPoints: _lineDrawMode ? _lineDraftPoints : const [],
                lineDraftCursor: _lineDrawMode ? _aimCursor : null,
                lineDraftSegmentType: _lineDraftSegmentType,
                showHlbMarkings: _showDraftBuildings && !showHlbFormSheet,
                showHlbLines: _showHlbLines && !showHlbFormSheet,
                walkPath: session?.walkPath ?? const [],
                showWalkPath: _showWalkPath && !showHlbFormSheet,
                showBasemap: _showBasemap,
                transparentBackground: showHlbFormSheet,
                mapType: _basemap.googleType,
                navigationDestination: showNav ? start : null,
                navigationOrigin: userLatLng != null ? gmaps.LatLng(userLatLng.latitude, userLatLng.longitude) : null,
                fitToken: _fitToken,
                followUserLocation: _navigateMode,
                lockRotateGestures: false,
                onCameraTargetChanged: _lineDrawMode ? _onLineDrawCameraMove : null,
                onMapCenterReaderReady: (reader) => _readMapCenter = reader,
                onRouteLoaded: (route) => setState(() {
                  _route = route;
                  _loadingRoute = false;
                }),
                onMapLongPress: d.hasOfficialBoundary && _fineTuningLandmark == null && !_lineDrawMode
                    ? (latLng) => _onMapLongPress(context, d, latLng.latitude, latLng.longitude)
                    : null,
                onMapTap: null,
                fineTuningLandmarkId: _fineTuningLandmark?.id,
                fineTuningLandmarkPosition: _fineTunePosition,
                onLandmarkDrag: (id, pos) => setState(() => _fineTunePosition = pos),
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              if (showHlbFormSheet)
                MissionHlbFormSheetBackdrop(
                  query: _query,
                  showBoundary: _showBoundary,
                  showBuildings: _showDraftBuildings,
                  showLineFeatures: _showHlbLines,
                  showWalkPath: _showWalkPath,
                ),
              ValueListenableBuilder<Position?>(
                valueListenable: _positionNotifier,
                builder: (context, livePos, _) => mapLayer(livePos ?? widget.initialPosition),
              ),
              MissionMapLayersDismissBarrier(
                visible: _layersOpen,
                onDismiss: () => setState(() => _layersOpen = false),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: showNav ? 88 : 0),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 8,
                        right: missionMapRightHudGutter + 8,
                        child: completionAsync.maybeWhen(
                          data: (c) => MissionMapHudStatus(
                            title: d.ebCode == kDefaultEbCode ? 'My HLB' : 'HLB ${d.ebCode}',
                            subtitle: _phaseLabel(d),
                            icon: Icons.explore,
                            progressPercent: d.hasOfficialBoundary ? c.overallPercent : null,
                          ),
                          orElse: () => MissionMapHudStatus(
                            title: d.ebCode == kDefaultEbCode ? 'My HLB' : 'HLB ${d.ebCode}',
                            subtitle: _phaseLabel(d),
                            icon: Icons.explore,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MissionMapHudIconButton(
                              icon: Icons.center_focus_strong,
                              tooltip: strings.fitBoundary,
                              onPressed: () => setState(() => _fitToken++),
                            ),
                            const SizedBox(height: 8),
                            MissionMapLayersDrawer(
                              expanded: _layersOpen,
                              onToggle: () => setState(() => _layersOpen = !_layersOpen),
                              maxPanelHeight: missionMapHudMaxPanelHeight(
                                context,
                                topOffset: 104,
                                bottomReserved: hudBottomReserved,
                              ),
                              showOfficialMap: _showPdf,
                              showRegionPins: _showPins,
                              showBoundary: _showBoundary,
                              showRoute: _showRoute,
                              showStartMarker: _showStartMarker,
                              showDraftBuildings: _showDraftBuildings,
                              showHlbLines: _showHlbLines,
                              showWalkPath: _showWalkPath,
                              showBasemap: _showBasemap,
                              officialMapOpacity: _pdfOpacity,
                              basemap: _basemap,
                              onOfficialMapChanged: (v) => setState(() => _showPdf = v),
                              onRegionPinsChanged: (v) => setState(() => _showPins = v),
                              onBoundaryChanged: (v) => setState(() => _showBoundary = v),
                              onRouteChanged: (v) => setState(() => _showRoute = v),
                              onStartMarkerChanged: (v) => setState(() => _showStartMarker = v),
                              onDraftBuildingsChanged: (v) => setState(() => _showDraftBuildings = v),
                              onHlbLinesChanged: (v) => setState(() => _showHlbLines = v),
                              onWalkPathChanged: (v) => setState(() => _showWalkPath = v),
                              onBasemapVisibilityChanged: (v) => setState(() => _showBasemap = v),
                              onOpacityChanged: (v) => setState(() => _pdfOpacity = v),
                              onBasemapChanged: (v) => setState(() => _basemap = v),
                            ),
                          ],
                        ),
                      ),
                      if (showFineTune)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: bottomInset,
                          child: MissionLandmarkFineTuneBar(
                            landmarkName: _fineTuningLandmark!.name,
                            onSave: () => _saveLandmarkFineTune(),
                            onCancel: _cancelLandmarkFineTune,
                          ),
                        ),
                      if (showPlaceHud)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: bottomInset,
                          child: MissionMapPlaceHud(
                            strings: strings,
                            selected: _placeTool,
                            onToolSelected: (tool) => _onPlaceToolSelected(context, tool),
                            onPlace: () => _placeFromCrosshair(context, d),
                            onMore: () => _openMoreMenu(context, d),
                          ),
                        ),
                      if (showLegacyBar)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: bottomInset,
                          child: MissionMapBottomBar(
                            primaryLabel: primary.label,
                            primaryIcon: primary.icon,
                            primaryColor: primary.color,
                            onPrimary: primary.onTap,
                            onMore: () => _openMoreMenu(context, d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showAimCrosshair)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: MissionMapCrosshair()),
                  ),
                ),
              if (_lineDrawMode)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: bottomInset,
                  child: _LineDrawHud(
                    segmentType: _lineDraftSegmentType ?? 'pucca_road',
                    pointCount: _lineDraftPoints.length,
                    canAddPoint: true,
                    onAddPoint: _addLineDrawPoint,
                    onUndo: _lineDraftPoints.isNotEmpty ? _undoLinePoint : null,
                    onFinish: _lineDraftPoints.length >= 2 ? () => _finishLineDraw(context) : null,
                    onCancel: _cancelLineDraw,
                  ),
                ),
              if (showNav && AppConfig.hasGoogleMaps)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MissionNavigationBanner(
                    route: _route,
                    currentStepIndex: _stepIndex,
                    loading: _loadingRoute,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<gmaps.LatLng?> _readAimPoint() async {
    if (_readMapCenter != null) {
      try {
        return await _readMapCenter!();
      } catch (_) {}
    }
    return _aimCursor;
  }

  void _onLineDrawCameraMove(gmaps.LatLng target) {
    _aimCursor = target;
    final now = DateTime.now();
    if (_lastAimCursorPaint != null &&
        now.difference(_lastAimCursorPaint!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAimCursorPaint = now;
    if (mounted) setState(() {});
  }

  void _onPlaceToolSelected(BuildContext context, MapPlaceTool tool) {
    if (tool == MapPlaceTool.line) {
      _enterLineDrawMode();
      return;
    }
    setState(() {
      if (_lineDrawMode) {
        _lineDrawMode = false;
        _lineDraftSegmentType = null;
        _lineDraftPoints.clear();
      }
      _placeTool = tool;
    });
  }

  Future<void> _placeFromCrosshair(BuildContext context, DiscoveryStatus d) async {
    if (_placeTool == MapPlaceTool.line) {
      _enterLineDrawMode();
      return;
    }
    final pt = await _readAimPoint();
    if (pt == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move the map — waiting for crosshair position')),
      );
      return;
    }
    if (!context.mounted) return;
    switch (_placeTool) {
      case MapPlaceTool.building:
        await _markBuildingAt(context, d, pt.latitude, pt.longitude);
      case MapPlaceTool.feature:
        await _markLandmarkAt(context, d, pt.latitude, pt.longitude);
      case MapPlaceTool.line:
        break;
    }
  }

  void _enterLineDrawMode() {
    setState(() {
      _lineDrawMode = true;
      _placeTool = MapPlaceTool.line;
      _lineDraftSegmentType ??= 'pucca_road';
      _lineDraftPoints.clear();
      _layersOpen = false;
      _fineTuningLandmark = null;
    });
  }

  void _cancelLineDraw() {
    setState(() {
      _lineDrawMode = false;
      _placeTool = MapPlaceTool.building;
      _lineDraftSegmentType = null;
      _lineDraftPoints.clear();
    });
  }

  void _undoLinePoint() {
    if (_lineDraftPoints.isEmpty) return;
    setState(() => _lineDraftPoints.removeLast());
  }

  Future<void> _addLineDrawPoint() async {
    final center = await _readAimPoint();
    if (center == null || !mounted) return;

    if (_lineDraftPoints.isNotEmpty) {
      final last = _lineDraftPoints.last;
      final gap = HlbGeoEngine.haversineMeters(
        last.latitude,
        last.longitude,
        center.latitude,
        center.longitude,
      );
      if (gap < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pan the map so the crosshair moves — points must be at least 2 m apart'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    setState(() {
      _lineDraftPoints.add(center);
      _aimCursor = center;
    });
  }

  List<gmaps.LatLng> _collapseLinePoints(List<gmaps.LatLng> points) {
    if (points.length < 2) return points;
    final out = <gmaps.LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final prev = out.last;
      final next = points[i];
      if (HlbGeoEngine.haversineMeters(prev.latitude, prev.longitude, next.latitude, next.longitude) >= 1) {
        out.add(next);
      }
    }
    return out;
  }

  Future<void> _finishLineDraw(BuildContext context) async {
    final draft = _collapseLinePoints(List<gmaps.LatLng>.from(_lineDraftPoints));
    if (draft.length < 2) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least 2 different points along the road')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final result = await MissionHlbMarkSheet.showLineFeature(
      context,
      pointCount: draft.length,
      initialSegmentType: _lineDraftSegmentType,
    );
    if (result == null || !context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.confirmRoadSegment(
      widget.ebId,
      draft.map((p) => (lat: p.latitude, lng: p.longitude)).toList(),
      segmentType: result.segmentType,
      name: result.name,
    );
    _cancelLineDraw();
    if (!_showHlbLines) {
      setState(() => _showHlbLines = true);
    }
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
    if (!mounted) return;
    setState(() => _fitToken++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${HlbOfficialCatalog.lineFeatureLabel(result.segmentType)} saved ($draft.length points)')),
    );
  }

  void _onMapLongPress(BuildContext context, DiscoveryStatus d, double lat, double lng) {
    if (!_showDraftBuildings) return;
    final hit = nearestHlbLandmark(_session?.hlbLandmarks ?? const [], lat, lng);
    if (hit != null) {
      _beginLandmarkFineTune(hit);
    }
  }

  void _beginLandmarkFineTune(MissionHlbLandmarkPin landmark) {
    setState(() {
      _fineTuningLandmark = landmark;
      _fineTuneOriginal = gmaps.LatLng(landmark.latitude, landmark.longitude);
      _fineTunePosition = _fineTuneOriginal;
      _layersOpen = false;
    });
  }

  void _cancelLandmarkFineTune() {
    setState(() {
      _fineTuningLandmark = null;
      _fineTunePosition = null;
      _fineTuneOriginal = null;
    });
  }

  Future<void> _saveLandmarkFineTune() async {
    final landmark = _fineTuningLandmark;
    final position = _fineTunePosition;
    if (landmark == null || position == null) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.updateLandmarkPosition(
      widget.ebId,
      localId: landmark.id,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    _cancelLandmarkFineTune();
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
  }

  Future<bool> _confirmMarkLocation(double lat, double lng) async {
    final local = ref.read(missionLocalFirstProvider);
    final state = await local.getRawState(widget.ebId);
    if (state == null || !state.hasOfficialBoundary) return true;
    if (local.isInsideOfficialBoundary(state, lat, lng)) return true;
    if (!mounted) return false;

    final override = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Outside assigned HLB'),
        content: const Text(
          'This point is outside your official HLB boundary.\n\n'
          'Confirm only if you are certain it belongs to this block.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Confirm anyway'),
          ),
        ],
      ),
    );
    if (override != true) return false;

    await local.recordOutsideBoundaryDiscovery(
      widget.ebId,
      latitude: lat,
      longitude: lng,
      label: 'Manual mark outside boundary',
      overridden: true,
    );
    return true;
  }

  Future<void> _markBuildingAt(
    BuildContext context,
    DiscoveryStatus d,
    double lat,
    double lng,
  ) async {
    if (!await _confirmMarkLocation(lat, lng)) return;
    if (!context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    final suggested = await local.suggestBuildingNumber(widget.ebId, lat, lng);
    if (!context.mounted) return;
    final result = await MissionHlbMarkSheet.showBuilding(
      context,
      suggestedNumber: suggested,
      locationHint: 'Crosshair marks the spot — pan, zoom & rotate until it is right',
    );
    if (result == null || !context.mounted) return;

    await local.discoverBuilding(
      widget.ebId,
      latitude: lat,
      longitude: lng,
      buildingType: result.buildingType,
      buildingNumber: result.buildingNumber,
      censusHouseCount: result.censusHouseCount,
    );
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
  }

  Future<void> _markLandmarkAt(
    BuildContext context,
    DiscoveryStatus d,
    double lat,
    double lng,
  ) async {
    if (!await _confirmMarkLocation(lat, lng)) return;
    if (!context.mounted) return;

    final result = await MissionHlbMarkSheet.showLandmark(
      context,
      locationHint: 'Temple, mosque, school, shop… — placed at crosshair',
    );
    if (result == null || !context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.discoverLandmark(
      widget.ebId,
      name: result.name,
      landmarkType: result.landmarkType,
      latitude: lat,
      longitude: lng,
    );
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
  }

  void _showDraftSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Consumer(
          builder: (context, ref, _) {
            final mapAsync = ref.watch(draftMapProvider(_query));
            final templateAsync = ref.watch(hlbExportTemplateProvider(_query));
            return mapAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (map) => ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Text('HLB layout map', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.open_in_full),
                        tooltip: 'Full screen',
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/mission/${widget.projectId}/eb/${widget.ebId}/draft-map');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  templateAsync.when(
                    loading: () => const AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (layout) => AspectRatio(
                      aspectRatio: layout.pageSize.widthPt / layout.pageSize.heightPt,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: HlbTemplateSheetPreview(mapData: map, layout: layout),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${map.buildings.length} buildings · ${map.landmarks.length} landmarks · ${map.lineFeatures.length} lines',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  MissionLineFeatureHistoryPanel(
                    projectId: widget.projectId,
                    ebId: widget.ebId,
                    lines: map.lineFeatures,
                    onChanged: () => _reloadSession(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LineDrawHud extends StatelessWidget {
  const _LineDrawHud({
    required this.segmentType,
    required this.pointCount,
    required this.onCancel,
    required this.onAddPoint,
    this.canAddPoint = true,
    this.onUndo,
    this.onFinish,
  });

  final String segmentType;
  final int pointCount;
  final bool canAddPoint;
  final VoidCallback onAddPoint;
  final VoidCallback? onUndo;
  final VoidCallback? onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final typeLabel = HlbOfficialCatalog.lineFeatureLabel(segmentType);
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: Colors.black.withValues(alpha: 0.9),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Drawing: $typeLabel',
                style: const TextStyle(color: Color(0xFF42A5F5), fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Pan · zoom · rotate · $pointCount point${pointCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(onPressed: onCancel, child: const Text('Cancel')),
                  if (onUndo != null)
                    TextButton(onPressed: onUndo, child: const Text('Undo')),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: canAddPoint ? onAddPoint : null,
                      icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                      label: const Text('Add point'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white24,
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onFinish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF42A5F5),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white24,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Finish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Map-first lobby when no active HLB is selected.
class MissionMapLobbyScreen extends ConsumerStatefulWidget {
  const MissionMapLobbyScreen({this.projectId, this.initialPosition, super.key});

  final String? projectId;
  final Position? initialPosition;

  @override
  ConsumerState<MissionMapLobbyScreen> createState() => _MissionMapLobbyScreenState();
}

class _MissionMapLobbyScreenState extends ConsumerState<MissionMapLobbyScreen> with MissionGpsTracking {
  var _basemap = MissionMapBasemap.hybrid;
  var _fitToken = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      position = widget.initialPosition;
    }
    bootMissionGps(ebId: 'lobby', onPosition: (_) => setState(() {}), onBreadcrumb: (_) {});
  }

  @override
  void dispose() {
    stopMissionGps();
    super.dispose();
  }

  Future<void> _importHloPdf(BuildContext context) async {
    final projectId = widget.projectId;
    if (projectId == null) return;
    final eb = await ensureEnumeratorEb(ref, projectId);
    if (context.mounted) {
      context.push('/mission/$projectId/eb/${eb.id}/georef');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = position ?? widget.initialPosition;
    final userLatLng = pos != null ? LatLng(pos.latitude, pos.longitude) : null;
    const center = LatLng(20.5937, 78.9629);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MissionMapCanvas(
            center: center,
            boundary: const [],
            userPosition: userLatLng,
            mapType: _basemap.googleType,
            fitToken: _fitToken,
            followUserLocation: true,
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  child: MissionMapHudStatus(
                    title: 'HLB Field Guide',
                    subtitle: pos != null
                        ? 'Import your HLO PDF to begin'
                        : 'Waiting for GPS…',
                    icon: Icons.explore,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MissionMapHudIconButton(
                        icon: _basemap.icon,
                        tooltip: 'Switch basemap',
                        onPressed: () {
                          final modes = MissionMapBasemap.values;
                          final next = modes[(_basemap.index + 1) % modes.length];
                          setState(() => _basemap = next);
                        },
                      ),
                      const SizedBox(width: 6),
                      MissionMapHudIconButton(
                        icon: Icons.folder_outlined,
                        tooltip: 'Projects',
                        onPressed: () => context.push('/projects'),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Material(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withValues(alpha: 0.88),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: widget.projectId != null
                                  ? () => _importHloPdf(context)
                                  : () => context.push('/projects'),
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(widget.projectId != null ? 'Import HLO PDF' : 'Choose project'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00897B),
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
