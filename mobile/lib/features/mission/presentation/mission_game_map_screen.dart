import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_directions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hlb_geo_engine.dart';
import '../data/mission_map_session.dart';
import '../widgets/bearing_arrow.dart';
import '../widgets/hlb_map_painter.dart';
import '../widgets/mission_hlb_mark_sheet.dart';
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
  var _showWalkPath = true;
  var _showBasemap = true;
  var _pdfOpacity = 0.45;
  var _basemap = MissionMapBasemap.hybrid;

  MissionHlbLandmarkPin? _fineTuningLandmark;
  gmaps.LatLng? _fineTunePosition;
  gmaps.LatLng? _fineTuneOriginal;

  var _lineDrawMode = false;
  final List<gmaps.LatLng> _lineDraftPoints = [];

  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      position = widget.initialPosition;
    }
    _boot();
  }

  Future<void> _boot() async {
    await bootMissionGps(
      ebId: widget.ebId,
      onPosition: (_) {
        _updateStepIndex();
        setState(() {});
      },
      onBreadcrumb: (_) {},
    );
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
    stopMissionGps();
    super.dispose();
  }

  String _phaseLabel(DiscoveryStatus d) {
    if (_fineTuningLandmark != null) {
      return 'Drag feature · long-press symbol to fine-tune';
    }
    if (!d.hasOfficialBoundary) return 'Import HLO PDF to place your block on the map';
    if (d.buildingsDiscovered == 0) {
      return 'Mark buildings with □ △ ▨ — tap Add building or long-press map';
    }
    return '${d.buildingsDiscovered} buildings · ${d.pathWalkedLabel}';
  }

  ({String label, IconData icon, Color color, VoidCallback onTap}) _primaryAction(
    DiscoveryStatus d, {
    required BuildContext context,
  }) {
    if (!d.hasOfficialBoundary) {
      return (
        label: 'Import HLO PDF',
        icon: Icons.upload_file_outlined,
        color: const Color(0xFF00897B),
        onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/georef'),
      );
    }
    if (_navigateMode) {
      return (
        label: 'Stop navigation',
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
      label: 'Add building',
      icon: Icons.home_work_outlined,
      color: const Color(0xFF00E676),
      onTap: () => _markBuildingAtGps(context, d),
    );
  }

  void _openMoreMenu(BuildContext context, DiscoveryStatus d) {
    setState(() => _layersOpen = false);
    showMissionMoreSheet(
      context,
      items: [
        if (d.hasOfficialBoundary && d.boundarySource == 'layout_map')
          MissionMoreSheetItem(
            icon: Icons.pin_drop_outlined,
            label: 'Redo map alignment',
            onTap: () async {
              await context.push('/mission/${widget.projectId}/eb/${widget.ebId}/realign');
              if (!mounted) return;
              await _reloadSession();
              ref.invalidate(discoveryStatusProvider(_query));
            },
          ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.place_outlined,
            label: 'Add map feature',
            onTap: () => _markLandmarkAtGps(context, d),
          ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.polyline_outlined,
            label: 'Draw road / canal',
            onTap: () => _startLineDraw(),
          ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.text_fields_outlined,
            label: 'Add map label',
            onTap: () => _markAnnotationAtGps(context),
          ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.link_outlined,
            label: 'Adjacent HLB reference',
            onTap: () => _markAdjacentHlbAtGps(context),
          ),
        if (d.hasOfficialBoundary)
          MissionMoreSheetItem(
            icon: Icons.videocam_outlined,
            label: 'Camera discovery walk',
            onTap: () => _startCapture(context, d),
          ),
        if (d.hasOfficialBoundary && _session?.startPoint != null)
          MissionMoreSheetItem(
            icon: Icons.navigation_outlined,
            label: 'Navigate to NW corner',
            onTap: () => setState(() {
              _navigateMode = true;
              _loadingRoute = AppConfig.hasGoogleMaps;
              _showRoute = true;
              _showStartMarker = true;
            }),
          ),
        MissionMoreSheetItem(
          icon: Icons.map_outlined,
          label: 'Draft map',
          onTap: () => _showDraftSheet(context),
        ),
        if (d.buildingsDiscovered > 0)
          MissionMoreSheetItem(
            icon: Icons.home_work_outlined,
            label: 'House listing',
            onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/listing'),
          ),
        MissionMoreSheetItem(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/dashboard'),
        ),
        MissionMoreSheetItem(
          icon: Icons.history,
          label: 'Walk replay',
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/replay'),
        ),
        MissionMoreSheetItem(
          icon: Icons.warning_amber_outlined,
          label: 'Coverage gaps',
          onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/gaps'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(discoveryStatusProvider(_query), (previous, next) {
      if (next.hasValue) {
        if (next.value!.buildingsDiscovered > 0) {
          _showDraftBuildings = true;
          _showWalkPath = true;
        }
        _reloadSession();
      }
    });

    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final completionAsync = ref.watch(missionCompletionProvider(_query));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final session = _session;
          final pos = position ?? widget.initialPosition;
          final userLatLng = pos != null ? LatLng(pos.latitude, pos.longitude) : null;
          final boundary = session?.boundaryRing ?? [];
          final center = session?.mapCenter ??
              MissionSatelliteMap.boundsCenter(boundary) ??
              const LatLng(20.59, 78.96);
          final start = session?.startPoint;
          final showNav = _navigateMode && start != null && d.hasOfficialBoundary;
          final hudBottomReserved = (showNav ? 96.0 : 0) + 88.0;
          final primary = _primaryAction(d, context: context);

          return Stack(
            fit: StackFit.expand,
            children: [
              MissionMapCanvas(
                center: center,
                boundary: boundary,
                userPosition: userLatLng,
                mode: MissionMapMode.mission,
                showPdfOverlay: _showPdf && session?.layoutImagePath != null && session?.imageBounds != null,
                pdfImageUrl: session?.layoutImagePath,
                pdfBounds: session?.imageBounds,
                pdfOpacity: _pdfOpacity,
                showRegionPins: _showPins,
                showBoundary: _showBoundary,
                showNavigationRoute: _showRoute && showNav,
                showStartMarker: _showStartMarker && start != null,
                draftPins: session?.draftPins ?? const [],
                showDraftPins: false,
                hlbBuildings: session?.hlbBuildings ?? const [],
                hlbLandmarks: session?.hlbLandmarks ?? const [],
                hlbLineFeatures: session?.hlbLineFeatures ?? const [],
                lineDraftPoints: _lineDrawMode ? _lineDraftPoints : const [],
                showHlbMarkings: _showDraftBuildings,
                walkPath: session?.walkPath ?? const [],
                showWalkPath: _showWalkPath,
                showBasemap: _showBasemap,
                mapType: _basemap.googleType,
                navigationDestination: showNav ? start : null,
                navigationOrigin: pos != null ? gmaps.LatLng(pos.latitude, pos.longitude) : null,
                fitToken: _fitToken,
                followUserLocation: true,
                onRouteLoaded: (route) => setState(() {
                  _route = route;
                  _loadingRoute = false;
                }),
                onMapLongPress: d.hasOfficialBoundary && _fineTuningLandmark == null && !_lineDrawMode
                    ? (latLng) => _onMapLongPress(context, d, latLng.latitude, latLng.longitude)
                    : null,
                onMapTap: _lineDrawMode
                    ? (latLng) => _onLineDrawTap(latLng.latitude, latLng.longitude)
                    : null,
                fineTuningLandmarkId: _fineTuningLandmark?.id,
                fineTuningLandmarkPosition: _fineTunePosition,
                onLandmarkDrag: (id, pos) => setState(() => _fineTunePosition = pos),
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
                        right: 96,
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
                            MissionMapLayersDrawer(
                              expanded: _layersOpen,
                              onToggle: () => setState(() => _layersOpen = !_layersOpen),
                              maxPanelHeight: missionMapHudMaxPanelHeight(
                                context,
                                bottomReserved: hudBottomReserved,
                              ),
                              showOfficialMap: _showPdf,
                              showRegionPins: _showPins,
                              showBoundary: _showBoundary,
                              showRoute: _showRoute,
                              showStartMarker: _showStartMarker,
                              showDraftBuildings: _showDraftBuildings,
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
                              onWalkPathChanged: (v) => setState(() => _showWalkPath = v),
                              onBasemapVisibilityChanged: (v) => setState(() => _showBasemap = v),
                              onOpacityChanged: (v) => setState(() => _pdfOpacity = v),
                              onBasemapChanged: (v) => setState(() => _basemap = v),
                            ),
                            const SizedBox(height: 8),
                            MissionMapHudIconButton(
                              icon: Icons.center_focus_strong,
                              tooltip: 'Fit boundary',
                              onPressed: () => setState(() => _fitToken++),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: showNav && AppConfig.hasGoogleMaps ? 104 : 16,
                        child: _fineTuningLandmark != null
                            ? MissionLandmarkFineTuneBar(
                                landmarkName: _fineTuningLandmark!.name,
                                onSave: () => _saveLandmarkFineTune(),
                                onCancel: _cancelLandmarkFineTune,
                              )
                            : MissionMapBottomBar(
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
              if (_lineDrawMode)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: showNav ? 96 : 88,
                  child: _LineDrawHud(
                    pointCount: _lineDraftPoints.length,
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

  void _startLineDraw() {
    setState(() {
      _lineDrawMode = true;
      _lineDraftPoints.clear();
      _layersOpen = false;
      _fineTuningLandmark = null;
    });
  }

  void _cancelLineDraw() {
    setState(() {
      _lineDrawMode = false;
      _lineDraftPoints.clear();
    });
  }

  void _undoLinePoint() {
    if (_lineDraftPoints.isEmpty) return;
    setState(() => _lineDraftPoints.removeLast());
  }

  void _onLineDrawTap(double lat, double lng) {
    setState(() => _lineDraftPoints.add(gmaps.LatLng(lat, lng)));
  }

  Future<void> _finishLineDraw(BuildContext context) async {
    if (_lineDraftPoints.length < 2) return;
    if (!context.mounted) return;

    final result = await MissionHlbMarkSheet.showLineFeature(
      context,
      pointCount: _lineDraftPoints.length,
    );
    if (result == null || !context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.confirmRoadSegment(
      widget.ebId,
      _lineDraftPoints.map((p) => (lat: p.latitude, lng: p.longitude)).toList(),
      segmentType: result.segmentType,
      name: result.name,
    );
    _cancelLineDraw();
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
  }

  void _onMapLongPress(BuildContext context, DiscoveryStatus d, double lat, double lng) {
    if (_showDraftBuildings) {
      final hit = nearestHlbLandmark(_session?.hlbLandmarks ?? const [], lat, lng);
      if (hit != null) {
        _beginLandmarkFineTune(hit);
        return;
      }
    }
    _markBuildingAt(context, d, lat, lng);
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

  Future<void> _markBuildingAtGps(BuildContext context, DiscoveryStatus d) async {
    final pos = position ?? widget.initialPosition;
    if (pos == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS — try again in a moment')),
      );
      return;
    }
    await _markBuildingAt(context, d, pos.latitude, pos.longitude);
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
      locationHint: 'Long-press map to pick a different spot',
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

  Future<void> _markLandmarkAtGps(BuildContext context, DiscoveryStatus d) async {
    final pos = position ?? widget.initialPosition;
    if (pos == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS — try again in a moment')),
      );
      return;
    }
    if (!await _confirmMarkLocation(pos.latitude, pos.longitude)) return;
    if (!context.mounted) return;

    final result = await MissionHlbMarkSheet.showLandmark(context);
    if (result == null || !context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.discoverLandmark(
      widget.ebId,
      name: result.name,
      landmarkType: result.landmarkType,
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
    await _reloadSession();
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
  }

  Future<void> _markAnnotationAtGps(BuildContext context) async {
    final pos = position ?? widget.initialPosition;
    if (pos == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS — try again in a moment')),
      );
      return;
    }
    await _markAnnotationAt(context, pos.latitude, pos.longitude);
  }

  Future<void> _markAdjacentHlbAtGps(BuildContext context) async {
    final pos = position ?? widget.initialPosition;
    if (pos == null) return;
    if (!context.mounted) return;
    final result = await MissionHlbMarkSheet.showMapAnnotation(
      context,
      initialType: 'adjacent_hlb',
      initialText: 'HLB NO: ',
    );
    if (result == null || !context.mounted) return;
    if (!await _confirmMarkLocation(pos.latitude, pos.longitude)) return;
    final local = ref.read(missionLocalFirstProvider);
    await local.addMapAnnotation(
      widget.ebId,
      text: result.text,
      annotationType: result.annotationType,
      latitude: pos.latitude,
      longitude: pos.longitude,
      rotationDegrees: result.rotationDegrees,
    );
    ref.invalidate(draftMapProvider(_query));
  }

  Future<void> _markAnnotationAt(BuildContext context, double lat, double lng) async {
    if (!await _confirmMarkLocation(lat, lng)) return;
    if (!context.mounted) return;
    final result = await MissionHlbMarkSheet.showMapAnnotation(context);
    if (result == null || !context.mounted) return;
    final local = ref.read(missionLocalFirstProvider);
    await local.addMapAnnotation(
      widget.ebId,
      text: result.text,
      annotationType: result.annotationType,
      latitude: lat,
      longitude: lng,
      rotationDegrees: result.rotationDegrees,
    );
    ref.invalidate(draftMapProvider(_query));
  }

  Future<void> _startCapture(BuildContext context, DiscoveryStatus d) async {
    final local = ref.read(missionLocalFirstProvider);
    await local.recordBoundaryAudit(widget.ebId, 'discovery_started');
    ref.invalidate(discoveryStatusProvider(_query));
    if (context.mounted) {
      await context.push('/mission/${widget.projectId}/eb/${widget.ebId}/discover-walk');
      await _reloadSession();
      ref.invalidate(discoveryStatusProvider(_query));
      ref.invalidate(draftMapProvider(_query));
    }
  }

  void _showDraftSheet(BuildContext context) {
    final mapAsync = ref.read(draftMapProvider(_query));
    mapAsync.whenData((map) {
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
          builder: (_, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Text('Draft census map', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
              AspectRatio(
                aspectRatio: 4 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: HlbMapPainter(mapData: map),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${map.buildings.length} buildings · ${map.landmarks.length} landmarks · ${map.lineFeatures.length} lines',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _LineDrawHud extends StatelessWidget {
  const _LineDrawHud({
    required this.pointCount,
    required this.onCancel,
    this.onUndo,
    this.onFinish,
  });

  final int pointCount;
  final VoidCallback? onUndo;
  final VoidCallback? onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      color: Colors.black.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tap map to trace road, canal, or path · $pointCount point${pointCount == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                if (onUndo != null) ...[
                  const SizedBox(width: 4),
                  TextButton(onPressed: onUndo, child: const Text('Undo')),
                ],
                const Spacer(),
                ElevatedButton(
                  onPressed: onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF42A5F5),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white24,
                  ),
                  child: const Text('Finish line'),
                ),
              ],
            ),
          ],
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
