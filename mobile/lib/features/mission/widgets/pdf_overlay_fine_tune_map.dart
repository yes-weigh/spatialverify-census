import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../data/mission_map_helpers.dart';
import '../data/mission_map_style.dart';
import '../data/satellite_align_math.dart';
import '../models/layout_georef_models.dart';
import 'mission_satellite_map.dart';

enum _FineTuneHandleKind { corner, edge, center }

class _FineTuneDragSession {
  const _FineTuneDragSession({
    required this.baseBounds,
    required this.startFinger,
    required this.kind,
    this.cornerIndex,
    this.edgeIndex,
  });

  final ImageBounds baseBounds;
  final LatLng startFinger;
  final _FineTuneHandleKind kind;
  final int? cornerIndex;
  final int? edgeIndex;
}

/// Satellite map with PDF overlay resize (corners) and rotate (edges) handles.
class PdfOverlayFineTuneMap extends StatefulWidget {
  const PdfOverlayFineTuneMap({
    required this.boundary,
    required this.initialBounds,
    required this.pdfImageUrl,
    required this.onBoundsChanged,
    this.pdfOpacity = 0.55,
    this.maskOutsideBoundary = false,
    this.boundaryUvRing = const [],
    this.onMapReady,
    super.key,
  });

  final List<GpsPoint> boundary;
  final ImageBounds initialBounds;
  final String pdfImageUrl;
  final double pdfOpacity;
  final bool maskOutsideBoundary;
  final List<({double x, double y})> boundaryUvRing;
  final ValueChanged<ImageBounds> onBoundsChanged;
  final void Function(Future<void> Function() fitCamera)? onMapReady;

  @override
  State<PdfOverlayFineTuneMap> createState() => _PdfOverlayFineTuneMapState();
}

class _PdfOverlayFineTuneMapState extends State<PdfOverlayFineTuneMap> {
  gmaps.GoogleMapController? _controller;
  gmaps.BytesMapBitmap? _pdfBitmap;
  var _bitmapKey = '';
  late ImageBounds _liveBounds;
  _FineTuneDragSession? _dragSession;
  var _isDragging = false;

  @override
  void initState() {
    super.initState();
    _liveBounds = widget.initialBounds;
    _loadPdfBitmap();
  }

  @override
  void didUpdateWidget(PdfOverlayFineTuneMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.initialBounds != widget.initialBounds) {
      _liveBounds = widget.initialBounds;
    }
    final key = _overlayBitmapKey();
    if (key != _bitmapKey ||
        oldWidget.pdfImageUrl != widget.pdfImageUrl ||
        oldWidget.maskOutsideBoundary != widget.maskOutsideBoundary) {
      _loadPdfBitmap();
    }
  }

  String _overlayBitmapKey() =>
      '${widget.pdfImageUrl}|mask:${widget.maskOutsideBoundary}|${widget.boundaryUvRing.length}';

  Future<void> _loadPdfBitmap() async {
    final key = _overlayBitmapKey();
    final bitmap = await loadLayoutGroundOverlayBitmap(
      widget.pdfImageUrl,
      maskOutsideUvRing: widget.maskOutsideBoundary,
      uvRing: widget.boundaryUvRing,
    );
    if (!mounted) return;
    setState(() {
      _pdfBitmap = bitmap;
      _bitmapKey = key;
    });
  }

  void _beginDrag({
    required _FineTuneHandleKind kind,
    required LatLng finger,
    int? cornerIndex,
    int? edgeIndex,
  }) {
    _dragSession = _FineTuneDragSession(
      baseBounds: _liveBounds,
      startFinger: finger,
      kind: kind,
      cornerIndex: cornerIndex,
      edgeIndex: edgeIndex,
    );
    _isDragging = true;
  }

  void _endDrag(LatLng finger) {
    final session = _dragSession;
    if (session == null) return;

    final ImageBounds next = switch (session.kind) {
      _FineTuneHandleKind.center => SatelliteAlignMath.fineTuneShift(
          session.baseBounds,
          session.startFinger,
          finger,
        ),
      _FineTuneHandleKind.corner => SatelliteAlignMath.fineTuneResizeCorner(
          session.baseBounds,
          session.cornerIndex!,
          session.startFinger,
          finger,
        ),
      _FineTuneHandleKind.edge => SatelliteAlignMath.fineTuneRotate(
          session.baseBounds,
          session.startFinger,
          finger,
        ),
    };

    _dragSession = null;
    _isDragging = false;
    setState(() => _liveBounds = next);
    widget.onBoundsChanged(next);
  }

  Set<gmaps.GroundOverlay> _buildGroundOverlays() {
    if (_pdfBitmap == null) return {};
    return {
      gmaps.GroundOverlay.fromBounds(
        groundOverlayId: const gmaps.GroundOverlayId('hlo_layout_overlay'),
        image: _pdfBitmap!,
        bounds: imageBoundsToGoogle(_liveBounds),
        transparency: (1 - widget.pdfOpacity.clamp(0.0, 1.0)).clamp(0.0, 1.0),
        bearing: SatelliteAlignMath.normalizeMapBearing(_liveBounds.rotation),
        clickable: false,
        zIndex: 1,
      ),
    };
  }

  Future<void> _fitCamera() async {
    final controller = _controller;
    if (controller == null) return;

    final points = <gmaps.LatLng>[
      ...boundaryToGoogle(widget.boundary),
      ...SatelliteAlignMath.overlayCornerPositions(_liveBounds)
          .map((p) => gmaps.LatLng(p.latitude, p.longitude)),
    ];
    if (points.isEmpty) return;

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
      gmaps.CameraUpdate.newLatLngBounds(
        gmaps.LatLngBounds(
          southwest: gmaps.LatLng(minLat, minLng),
          northeast: gmaps.LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }

  gmaps.Marker _cornerMarker(int i, LatLng position) {
    return gmaps.Marker(
      markerId: gmaps.MarkerId('pdf_corner_$i'),
      position: gmaps.LatLng(position.latitude, position.longitude),
      draggable: true,
      zIndexInt: 3,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueOrange),
      infoWindow: gmaps.InfoWindow(title: 'Resize corner ${i + 1}'),
      onDragStart: (pos) => _beginDrag(
        kind: _FineTuneHandleKind.corner,
        finger: LatLng(pos.latitude, pos.longitude),
        cornerIndex: i,
      ),
      onDragEnd: (pos) => _endDrag(LatLng(pos.latitude, pos.longitude)),
    );
  }

  gmaps.Marker _edgeMarker(int i, LatLng position) {
    return gmaps.Marker(
      markerId: gmaps.MarkerId('pdf_edge_$i'),
      position: gmaps.LatLng(position.latitude, position.longitude),
      draggable: true,
      zIndexInt: 2,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueViolet),
      infoWindow: gmaps.InfoWindow(title: 'Rotate edge ${i + 1}'),
      onDragStart: (pos) => _beginDrag(
        kind: _FineTuneHandleKind.edge,
        finger: LatLng(pos.latitude, pos.longitude),
        edgeIndex: i,
      ),
      onDragEnd: (pos) => _endDrag(LatLng(pos.latitude, pos.longitude)),
    );
  }

  Set<gmaps.Marker> _buildMarkers() {
    final markers = <gmaps.Marker>{};
    final corners = SatelliteAlignMath.overlayCornerPositions(_liveBounds);
    for (var i = 0; i < corners.length; i++) {
      markers.add(_cornerMarker(i, corners[i]));
    }

    final edges = SatelliteAlignMath.overlayEdgePositions(_liveBounds);
    for (var i = 0; i < edges.length; i++) {
      markers.add(_edgeMarker(i, edges[i]));
    }

    final center = _liveBounds.center;
    markers.add(
      gmaps.Marker(
        markerId: const gmaps.MarkerId('pdf_center'),
        position: gmaps.LatLng(center.latitude, center.longitude),
        draggable: true,
        zIndexInt: 4,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueCyan),
        infoWindow: const gmaps.InfoWindow(title: 'Move overlay'),
        onDragStart: (pos) => _beginDrag(
          kind: _FineTuneHandleKind.center,
          finger: LatLng(pos.latitude, pos.longitude),
        ),
        onDragEnd: (pos) => _endDrag(LatLng(pos.latitude, pos.longitude)),
      ),
    );

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final ring = boundaryToGoogle(widget.boundary);
    final initial = ring.isNotEmpty
        ? ring.first
        : MissionSatelliteMap.boundsCenter(widget.boundary) != null
            ? gmaps.LatLng(
                MissionSatelliteMap.boundsCenter(widget.boundary)!.latitude,
                MissionSatelliteMap.boundsCenter(widget.boundary)!.longitude,
              )
            : const gmaps.LatLng(10, 76);

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(target: initial, zoom: 18),
      mapType: gmaps.MapType.hybrid,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      compassEnabled: false,
      zoomControlsEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      groundOverlays: _buildGroundOverlays(),
      polylines: ring.length >= 2
          ? {
              gmaps.Polyline(
                polylineId: const gmaps.PolylineId('hlb_boundary'),
                points: [...ring, ring.first],
                color: MissionMapStyle.boundaryColor,
                width: MissionMapStyle.boundaryWidth.round(),
                patterns: MissionMapStyle.googleBoundaryPattern,
              ),
            }
          : {},
      markers: _buildMarkers(),
      onMapCreated: (c) async {
        _controller = c;
        widget.onMapReady?.call(_fitCamera);
        await _fitCamera();
      },
    );
  }
}
