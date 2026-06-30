import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_directions_service.dart';
import '../data/hlb_census_symbols.dart';
import '../data/hlb_feature_painter.dart';
import '../data/hlb_official_catalog.dart';
import '../data/mission_map_helpers.dart';
import '../data/mission_map_session.dart';
import '../data/mission_map_style.dart';
import '../data/satellite_align_math.dart';
import '../models/layout_georef_models.dart';
import 'mission_satellite_map.dart';

/// Google Maps canvas with HLB boundary, PDF overlay, route, and field markings.
class GoogleMissionMap extends StatefulWidget {
  const GoogleMissionMap({
    required this.center,
    required this.boundary,
    this.regions = const [],
    this.mode = MissionMapMode.prediction,
    this.boundaryDrawProgress = 1.0,
    this.showPdfOverlay = false,
    this.pdfImageUrl,
    this.pdfBounds,
    this.pdfOpacity = 0.45,
    this.boundaryUvRing = const [],
    this.showRegionPins = false,
    this.showBoundary = true,
    this.showNavigationRoute = true,
    this.showStartMarker = true,
    this.draftPins = const [],
    this.showDraftPins = true,
    this.hlbBuildings = const [],
    this.hlbLandmarks = const [],
    this.hlbLineFeatures = const [],
    this.lineDraftPoints = const [],
    this.lineDraftCursor,
    this.lineDraftSegmentType,
    this.showHlbMarkings = true,
    this.showHlbLines = true,
    this.walkPath = const [],
    this.showWalkPath = true,
    this.showBasemap = true,
    this.transparentBackground = false,
    this.mapType = MapType.hybrid,
    this.navigationDestination,
    this.navigationOrigin,
    this.travelMode = NavigationTravelMode.bicycling,
    this.fitToken = 0,
    this.userLocation,
    this.followUserLocation = true,
    this.lockCameraGestures = false,
    this.lockRotateGestures = false,
    this.onRouteLoaded,
    this.onMapLongPress,
    this.onMapTap,
    this.onCameraTargetChanged,
    this.onMapCenterReaderReady,
    this.fineTuningLandmarkId,
    this.fineTuningLandmarkPosition,
    this.onLandmarkDrag,
    super.key,
  });

  final LatLng center;
  final List<GpsPoint> boundary;
  final List<MapRegionMarker> regions;
  final MissionMapMode mode;
  final double boundaryDrawProgress;
  final bool showPdfOverlay;
  final String? pdfImageUrl;
  final ImageBounds? pdfBounds;
  final double pdfOpacity;
  final List<({double x, double y})> boundaryUvRing;
  final bool showRegionPins;
  final bool showBoundary;
  final bool showNavigationRoute;
  final bool showStartMarker;
  final List<MissionDraftPin> draftPins;
  final bool showDraftPins;
  final List<MissionHlbBuildingPin> hlbBuildings;
  final List<MissionHlbLandmarkPin> hlbLandmarks;
  final List<MissionMapLineFeature> hlbLineFeatures;
  final List<LatLng> lineDraftPoints;
  final LatLng? lineDraftCursor;
  final String? lineDraftSegmentType;
  final bool showHlbMarkings;
  final bool showHlbLines;
  final List<GpsPoint> walkPath;
  final bool showWalkPath;
  final bool showBasemap;
  final bool transparentBackground;
  final MapType mapType;
  final LatLng? navigationDestination;
  final LatLng? navigationOrigin;
  final NavigationTravelMode travelMode;
  final int fitToken;
  final LatLng? userLocation;
  final bool followUserLocation;
  final bool lockCameraGestures;
  final bool lockRotateGestures;
  final ValueChanged<DirectionsRoute?>? onRouteLoaded;
  final void Function(LatLng position)? onMapLongPress;
  final void Function(LatLng position)? onMapTap;
  final ValueChanged<LatLng>? onCameraTargetChanged;
  final void Function(Future<LatLng> Function() readCenter)? onMapCenterReaderReady;
  final String? fineTuningLandmarkId;
  final LatLng? fineTuningLandmarkPosition;
  final void Function(String landmarkId, LatLng position)? onLandmarkDrag;

  @override
  State<GoogleMissionMap> createState() => _GoogleMissionMapState();
}

class _GoogleMissionMapState extends State<GoogleMissionMap> {
  GoogleMapController? _controller;
  DirectionsRoute? _route;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Set<GroundOverlay> _groundOverlays = {};
  BytesMapBitmap? _pdfBitmap;
  int _overlayEpoch = 0;
  bool _loadingRoute = false;
  LatLng? _lastRouteKey;
  int _lastFitToken = 0;
  bool _centeredOnUser = false;
  LatLng? _lastCameraTarget;
  BitmapDescriptor? _userLocationIcon;
  final Map<String, BitmapDescriptor> _hlbBuildingIcons = {};
  final Map<String, BitmapDescriptor> _hlbLandmarkIcons = {};
  bool _loadingHlbIcons = false;

  static const _routeColor = Color(0xFF4285F4);
  static const _walkColor = Color(0xFF00E676);

  @override
  void initState() {
    super.initState();
    _lastFitToken = widget.fitToken;
    _rebuildOverlays();
    _loadPdfBitmap();
    _loadHlbIcons();
    _maybeFetchRoute();
    if (kIsWeb) {
      MissionMapStyle.userLocationGoogleIcon().then((icon) {
        if (!mounted) return;
        setState(() => _userLocationIcon = icon);
        _rebuildOverlays();
      });
    }
  }

  @override
  void didUpdateWidget(GoogleMissionMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pdfGeometryChanged = oldWidget.showPdfOverlay != widget.showPdfOverlay ||
        oldWidget.pdfImageUrl != widget.pdfImageUrl ||
        oldWidget.pdfBounds != widget.pdfBounds;

    if (pdfGeometryChanged) {
      if (oldWidget.pdfImageUrl != widget.pdfImageUrl) {
        _loadPdfBitmap();
      } else {
        _rebuildOverlays();
      }
    } else if (oldWidget.pdfOpacity != widget.pdfOpacity) {
      _rebuildGroundOverlaysOnly();
    }

    final mapDataChanged = oldWidget.boundary != widget.boundary ||
        oldWidget.boundaryUvRing != widget.boundaryUvRing ||
        oldWidget.boundaryDrawProgress != widget.boundaryDrawProgress ||
        oldWidget.regions != widget.regions ||
        oldWidget.showRegionPins != widget.showRegionPins ||
        oldWidget.showBoundary != widget.showBoundary ||
        oldWidget.showNavigationRoute != widget.showNavigationRoute ||
        oldWidget.showStartMarker != widget.showStartMarker ||
        oldWidget.draftPins != widget.draftPins ||
        oldWidget.showDraftPins != widget.showDraftPins ||
        oldWidget.hlbBuildings != widget.hlbBuildings ||
        oldWidget.hlbLandmarks != widget.hlbLandmarks ||
        oldWidget.hlbLineFeatures != widget.hlbLineFeatures ||
        oldWidget.lineDraftPoints != widget.lineDraftPoints ||
        oldWidget.lineDraftCursor != widget.lineDraftCursor ||
        oldWidget.lineDraftSegmentType != widget.lineDraftSegmentType ||
        oldWidget.showHlbMarkings != widget.showHlbMarkings ||
        oldWidget.showHlbLines != widget.showHlbLines ||
        oldWidget.fineTuningLandmarkId != widget.fineTuningLandmarkId ||
        oldWidget.fineTuningLandmarkPosition != widget.fineTuningLandmarkPosition ||
        oldWidget.walkPath != widget.walkPath ||
        oldWidget.showWalkPath != widget.showWalkPath ||
        oldWidget.navigationDestination != widget.navigationDestination ||
        oldWidget.navigationOrigin != widget.navigationOrigin;

    if (mapDataChanged) {
      _loadHlbIcons();
      _rebuildOverlays();
      _maybeFetchRoute(
        force: oldWidget.navigationDestination != widget.navigationDestination ||
            oldWidget.navigationOrigin != widget.navigationOrigin,
      );
    }

    final userMoved = oldWidget.userLocation?.latitude != widget.userLocation?.latitude ||
        oldWidget.userLocation?.longitude != widget.userLocation?.longitude;
    if (userMoved && kIsWeb) {
      _rebuildOverlays();
    }

    if (widget.fitToken != _lastFitToken) {
      _lastFitToken = widget.fitToken;
      _fitCamera(fitContent: true);
    } else {
      _tryCenterOnUser();
    }

    if (widget.onCameraTargetChanged != null && oldWidget.onCameraTargetChanged == null) {
      _reportCameraCenter();
    }
    if (widget.onMapCenterReaderReady != null &&
        (oldWidget.onMapCenterReaderReady == null || widget.fitToken != oldWidget.fitToken)) {
      widget.onMapCenterReaderReady!.call(_readMapCenter);
    }
  }

  Future<LatLng> _readMapCenter() async {
    final controller = _controller;
    if (controller == null) {
      return _lastCameraTarget ?? widget.userLocation ?? widget.center;
    }
    try {
      final region = await controller.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      _lastCameraTarget = center;
      return center;
    } catch (_) {
      return _lastCameraTarget ?? widget.userLocation ?? widget.center;
    }
  }

  Future<void> _reportCameraCenter() async {
    final controller = _controller;
    final callback = widget.onCameraTargetChanged;
    if (callback == null) return;

    if (_lastCameraTarget != null) {
      callback(_lastCameraTarget!);
      return;
    }

    if (controller == null) {
      callback(widget.userLocation ?? widget.center);
      return;
    }

    try {
      final region = await controller.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      _lastCameraTarget = center;
      callback(center);
    } catch (_) {
      callback(widget.userLocation ?? widget.center);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _lastCameraTarget = position.target;
    widget.onCameraTargetChanged?.call(position.target);
  }

  void _tryCenterOnUser() {
    if (!widget.followUserLocation || widget.userLocation == null) return;
    if (MissionMapCameraSession.hasAutoCenteredOnUser || _centeredOnUser) return;
    _centerOnUser(widget.userLocation!);
  }

  Future<void> _centerOnUser(LatLng location) async {
    if (MissionMapCameraSession.hasAutoCenteredOnUser) {
      _centeredOnUser = true;
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(location, 17));
    MissionMapCameraSession.hasAutoCenteredOnUser = true;
    _centeredOnUser = true;
  }

  Future<void> _loadPdfBitmap() async {
    final path = widget.pdfImageUrl;
    if (!widget.showPdfOverlay || path == null || path.isEmpty) {
      if (_pdfBitmap != null) {
        setState(() => _pdfBitmap = null);
        _rebuildOverlays();
      }
      return;
    }

    final bitmap = await loadLayoutGroundOverlayBitmap(path);
    if (!mounted) return;
    setState(() {
      _pdfBitmap = bitmap;
      _overlayEpoch++;
    });
    _rebuildOverlays();
  }

  Future<void> _loadHlbIcons() async {
    if (!widget.showHlbMarkings || _loadingHlbIcons) return;

    final buildingTypes = widget.hlbBuildings.map((b) => b.buildingType).toSet();
    final missingBuildings = buildingTypes.where((t) => !_hlbBuildingIcons.containsKey(t)).toList();
    final landmarkTypes = widget.hlbLandmarks
        .map((lm) => HlbOfficialCatalog.normalizeLandmarkType(lm.landmarkType))
        .toSet();
    final missingLandmarks = landmarkTypes.where((t) => !_hlbLandmarkIcons.containsKey(t)).toList();
    if (missingBuildings.isEmpty && missingLandmarks.isEmpty) return;

    _loadingHlbIcons = true;
    for (final type in missingBuildings) {
      _hlbBuildingIcons[type] = await HlbCensusSymbols.buildingMarker(type);
    }
    for (final type in missingLandmarks) {
      _hlbLandmarkIcons[type] = await HlbCensusSymbols.landmarkMarker(type);
    }
    _loadingHlbIcons = false;
    if (mounted) _rebuildOverlays();
  }

  Future<void> _maybeFetchRoute({bool force = false}) async {
    final dest = widget.navigationDestination;
    final origin = widget.navigationOrigin ?? widget.center;

    if (dest == null || !widget.showNavigationRoute || !AppConfig.hasGoogleMaps) {
      if (_route != null) {
        setState(() => _route = null);
        widget.onRouteLoaded?.call(null);
        _rebuildOverlays();
      }
      return;
    }

    final key = LatLng(
      (origin.latitude * 10000).round() / 10000,
      (origin.longitude * 10000).round() / 10000,
    );
    final destKey = LatLng(
      (dest.latitude * 10000).round() / 10000,
      (dest.longitude * 10000).round() / 10000,
    );
    final routeKey = LatLng(key.latitude + destKey.latitude, key.longitude + destKey.longitude);
    if (!force && _lastRouteKey == routeKey && _route != null) return;

    setState(() => _loadingRoute = true);
    final route = await GoogleDirectionsService().fetchRoute(
      origin: origin,
      destination: dest,
      mode: widget.travelMode,
    );
    if (!mounted) return;
    _lastRouteKey = routeKey;
    setState(() {
      _route = route;
      _loadingRoute = false;
    });
    widget.onRouteLoaded?.call(route);
    _rebuildOverlays();
    _fitCamera(fitContent: true);
  }

  List<GpsPoint> _effectiveBoundary() => missionMapBoundaryRing(
        storedRing: widget.boundary,
        uvRing: widget.boundaryUvRing,
        overlayBounds: widget.pdfBounds,
      );

  void _rebuildGroundOverlaysOnly() {
    if (!mounted) return;
    final groundOverlays = _buildGroundOverlays();
    setState(() => _groundOverlays = groundOverlays);
  }

  Set<GroundOverlay> _buildGroundOverlays() {
    final groundOverlays = <GroundOverlay>{};
    if (widget.showPdfOverlay &&
        widget.pdfImageUrl != null &&
        widget.pdfBounds != null &&
        _pdfBitmap != null) {
      final bounds = widget.pdfBounds!;
      groundOverlays.add(
        GroundOverlay.fromBounds(
          groundOverlayId: const GroundOverlayId('hlo_layout_overlay'),
          image: _pdfBitmap!,
          bounds: imageBoundsToGoogle(bounds),
          transparency: (1 - widget.pdfOpacity.clamp(0.0, 1.0)).clamp(0.0, 1.0),
          bearing: SatelliteAlignMath.normalizeMapBearing(bounds.rotation),
          clickable: false,
          zIndex: 1,
        ),
      );
    }
    return groundOverlays;
  }

  void _rebuildOverlays() {
    final boundaryComplete = widget.boundaryDrawProgress >= 0.99;
    final ring = boundaryToGoogle(_effectiveBoundary());
    final polylines = <Polyline>{};
    final markers = <Marker>{};
    final groundOverlays = _buildGroundOverlays();

    if (widget.showBoundary && ring.length >= 2) {
      final closed = [...ring];
      if (closed.first != closed.last) closed.add(closed.first);
      final total = closed.length;
      final take = (total * widget.boundaryDrawProgress.clamp(0, 1)).ceil().clamp(2, total);
      final partial = closed.sublist(0, take);

      polylines.add(Polyline(
        polylineId: const PolylineId('hlb_boundary'),
        points: partial,
        color: MissionMapStyle.boundaryColor,
        width: MissionMapStyle.boundaryWidth.round(),
        patterns: MissionMapStyle.googleBoundaryPatterns(complete: boundaryComplete),
      ));
    }

    if (widget.showWalkPath && widget.walkPath.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('walk_path'),
        points: widget.walkPath.map((p) => LatLng(p.lat, p.lng)).toList(),
        color: _walkColor,
        width: 4,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)],
      ));
    }

    if (widget.showHlbLines) {
      for (final seg in widget.hlbLineFeatures) {
        if (seg.points.length < 2) continue;
        final type = HlbOfficialCatalog.normalizeLineType(seg.segmentType);
        polylines.add(Polyline(
          polylineId: PolylineId('hlb_line_${seg.id}'),
          points: seg.points.map((p) => LatLng(p.lat, p.lng)).toList(),
          color: HlbFeaturePainter.lineFeatureColor(type),
          width: type == 'river' || type == 'canal' ? 6 : type == 'pucca_road' ? 7 : 5,
          patterns: _linePatterns(type),
          zIndex: 12,
        ));
      }
    }

    if (widget.lineDraftPoints.isNotEmpty || widget.lineDraftCursor != null) {
      final type = HlbOfficialCatalog.normalizeLineType(widget.lineDraftSegmentType ?? 'pucca_road');
      final color = HlbFeaturePainter.lineFeatureColor(type);
      final width = type == 'river' || type == 'canal' ? 5.0 : type == 'pucca_road' ? 6.0 : 4.0;

      if (widget.lineDraftPoints.length >= 2) {
        polylines.add(Polyline(
          polylineId: const PolylineId('line_draft'),
          points: widget.lineDraftPoints,
          color: color,
          width: width.round(),
          patterns: _linePatterns(type),
          zIndex: 15,
        ));
      }

      if (widget.lineDraftPoints.isNotEmpty && widget.lineDraftCursor != null) {
        polylines.add(Polyline(
          polylineId: const PolylineId('line_draft_preview'),
          points: [widget.lineDraftPoints.last, widget.lineDraftCursor!],
          color: color.withValues(alpha: 0.55),
          width: (width - 1).round().clamp(3, 8),
          patterns: [PatternItem.dash(8), PatternItem.gap(6)],
          zIndex: 16,
        ));
      }

      for (var i = 0; i < widget.lineDraftPoints.length; i++) {
        markers.add(Marker(
          markerId: MarkerId('line_draft_v_$i'),
          position: widget.lineDraftPoints[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 17,
          infoWindow: InfoWindow(title: 'Point ${i + 1}'),
        ));
      }
    }

    if (widget.showNavigationRoute && _route != null && _route!.points.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('navigation_route'),
        points: _route!.points,
        color: _routeColor,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ));
    }

    if (widget.showRegionPins) {
      for (final r in widget.regions) {
        if (!r.visible) continue;
        markers.add(Marker(
          markerId: MarkerId('region_${r.id}'),
          position: toGoogleLatLng(r.point),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            r.confirmed ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueAzure,
          ),
        ));
      }
    }

    if (widget.showHlbMarkings) {
      for (final b in widget.hlbBuildings) {
        final icon = _hlbBuildingIcons[b.buildingType];
        markers.add(Marker(
          markerId: MarkerId('hlb_b_${b.id}'),
          position: LatLng(b.latitude, b.longitude),
          icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: b.label,
            snippet: '${b.censusHouseCount} house(s) · ${HlbCensusSymbols.buildingTypes[b.buildingType] ?? b.buildingType}',
          ),
          zIndexInt: 12,
        ));
      }
      for (final lm in widget.hlbLandmarks) {
        final isFineTuning = lm.id == widget.fineTuningLandmarkId;
        final position = isFineTuning && widget.fineTuningLandmarkPosition != null
            ? widget.fineTuningLandmarkPosition!
            : LatLng(lm.latitude, lm.longitude);
        final landmarkType = HlbOfficialCatalog.normalizeLandmarkType(lm.landmarkType);
        final icon = _hlbLandmarkIcons[landmarkType];
        markers.add(Marker(
          markerId: MarkerId('hlb_lm_${lm.id}'),
          position: position,
          icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: lm.name,
            snippet: isFineTuning
                ? 'Drag to adjust · Save below'
                : '${HlbOfficialCatalog.landmarkLabel(landmarkType)} · long-press to fine-tune',
          ),
          draggable: isFineTuning,
          onDrag: isFineTuning ? (pos) => widget.onLandmarkDrag?.call(lm.id, pos) : null,
          onDragEnd: isFineTuning ? (pos) => widget.onLandmarkDrag?.call(lm.id, pos) : null,
          zIndexInt: isFineTuning ? 20 : 11,
        ));
      }
    } else if (widget.showDraftPins) {
      for (final pin in widget.draftPins) {
        markers.add(Marker(
          markerId: MarkerId('draft_${pin.id}'),
          position: LatLng(pin.latitude, pin.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: pin.label),
        ));
      }
    }

    if (widget.showStartMarker && widget.navigationDestination != null) {
      markers.add(Marker(
        markerId: const MarkerId('nav_destination'),
        position: widget.navigationDestination!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'HLB start', snippet: 'NW corner entry'),
      ));
    }

    if (kIsWeb && widget.userLocation != null && _userLocationIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: widget.userLocation!,
        icon: _userLocationIcon!,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndexInt: 999,
      ));
    }

    setState(() {
      _polylines = polylines;
      _markers = markers;
      _groundOverlays = groundOverlays;
    });
  }

  List<PatternItem> _linePatterns(String type) {
    switch (HlbOfficialCatalog.normalizeLineType(type)) {
      case 'kutcha_road':
        return [PatternItem.dash(10), PatternItem.gap(8)];
      case 'street':
        return [PatternItem.dash(8), PatternItem.gap(6)];
      case 'path':
        return [PatternItem.dot, PatternItem.gap(8)];
      case 'railway':
        return [PatternItem.dash(12), PatternItem.gap(8)];
      default:
        return [];
    }
  }

  Future<void> _fitCamera({bool fitContent = false}) async {
    final controller = _controller;
    if (controller == null) return;

    if (!fitContent &&
        widget.followUserLocation &&
        widget.userLocation != null &&
        !_centeredOnUser) {
      await _centerOnUser(widget.userLocation!);
      return;
    }

    if (!fitContent &&
        widget.followUserLocation &&
        widget.userLocation != null &&
        boundaryToGoogle(widget.boundary).isEmpty &&
        (_route == null || _route!.points.isEmpty)) {
      await _centerOnUser(widget.userLocation!);
      return;
    }

    final points = <LatLng>[...boundaryToGoogle(widget.boundary)];
    if (_route != null) points.addAll(_route!.points);
    if (widget.navigationDestination != null) points.add(widget.navigationDestination!);
    for (final pin in widget.draftPins) {
      points.add(LatLng(pin.latitude, pin.longitude));
    }
    for (final b in widget.hlbBuildings) {
      points.add(LatLng(b.latitude, b.longitude));
    }
    for (final line in widget.hlbLineFeatures) {
      for (final p in line.points) {
        points.add(LatLng(p.lat, p.lng));
      }
    }

    if (points.isEmpty) {
      final target = widget.userLocation ?? widget.center;
      if (widget.userLocation != null && widget.followUserLocation && !MissionMapCameraSession.hasAutoCenteredOnUser) {
        await _centerOnUser(widget.userLocation!);
      } else {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
      }
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.userLocation ??
        boundaryCenterGoogle(widget.boundary) ??
        widget.center;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!widget.showBasemap && !widget.transparentBackground)
          const ColoredBox(color: MissionMapStyle.basemapOffBackground),
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initial, zoom: 17),
          mapType: widget.mapType,
          style: widget.showBasemap ? null : MissionMapStyle.hiddenBasemapJson,
          myLocationEnabled: !kIsWeb,
          myLocationButtonEnabled: !kIsWeb && !widget.lockCameraGestures,
          compassEnabled: true,
          zoomControlsEnabled: false,
          scrollGesturesEnabled: !widget.lockCameraGestures,
          zoomGesturesEnabled: !widget.lockCameraGestures,
          rotateGesturesEnabled: !widget.lockCameraGestures && !widget.lockRotateGestures,
          tiltGesturesEnabled: false,
          polylines: _polylines,
          groundOverlays: _groundOverlays,
          markers: _markers,
          onLongPress: widget.onMapLongPress,
          onTap: widget.onMapTap,
          onCameraMove: widget.onCameraTargetChanged == null ? null : _onCameraMove,
          onCameraIdle: widget.onCameraTargetChanged == null ? null : _reportCameraCenter,
          onMapCreated: (c) async {
            _controller = c;
            widget.onMapCenterReaderReady?.call(_readMapCenter);
            _tryCenterOnUser();
            if (!_centeredOnUser && !widget.followUserLocation) {
              await _fitCamera(fitContent: true);
            }
            await _reportCameraCenter();
          },
        ),
        if (_loadingRoute)
          const Positioned(
            top: 12,
            right: 12,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
