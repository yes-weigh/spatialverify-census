import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../data/mission_map_helpers.dart';
import '../data/mission_map_style.dart';
import '../data/satellite_align_math.dart';
import '../models/layout_georef_models.dart';
import 'mission_satellite_map.dart';

/// Satellite map with corner handles for rigid boundary alignment.
class BoundaryCornerAdjustMap extends StatefulWidget {
  const BoundaryCornerAdjustMap({
    required this.boundary,
    required this.selectedCornerIndex,
    required this.lockedCorner1Index,
    required this.lockedCorner2Index,
    required this.lockedCount,
    required this.onCornerSelected,
    required this.onCornerDragged,
    this.regions = const [],
    this.showRegionPins = false,
    this.showPdfOverlay = true,
    this.pdfImageUrl,
    this.pdfBounds,
    this.pdfOpacity = 0.45,
    this.enableCornerDrag = false,
    this.onMapReady,
    super.key,
  });

  final List<GpsPoint> boundary;
  final int? selectedCornerIndex;
  final int? lockedCorner1Index;
  final int? lockedCorner2Index;
  final int lockedCount;
  final List<MapRegionMarker> regions;
  final bool showRegionPins;
  final bool showPdfOverlay;
  final String? pdfImageUrl;
  final ImageBounds? pdfBounds;
  final double pdfOpacity;
  final bool enableCornerDrag;
  final void Function(Future<void> Function() fitCamera)? onMapReady;
  final ValueChanged<int> onCornerSelected;
  final void Function(int cornerIndex, LatLng position) onCornerDragged;

  @override
  State<BoundaryCornerAdjustMap> createState() => _BoundaryCornerAdjustMapState();
}

class _BoundaryCornerAdjustMapState extends State<BoundaryCornerAdjustMap> {
  gmaps.GoogleMapController? _controller;
  gmaps.BytesMapBitmap? _pdfBitmap;
  int _overlayEpoch = 0;

  @override
  void initState() {
    super.initState();
    _loadPdfBitmap();
  }

  @override
  void didUpdateWidget(BoundaryCornerAdjustMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final overlayChanged = oldWidget.showPdfOverlay != widget.showPdfOverlay ||
        oldWidget.pdfImageUrl != widget.pdfImageUrl ||
        oldWidget.pdfBounds != widget.pdfBounds ||
        oldWidget.pdfOpacity != widget.pdfOpacity;

    if (overlayChanged) {
      if (oldWidget.pdfImageUrl != widget.pdfImageUrl) {
        _loadPdfBitmap();
      }
    }
  }

  Future<void> _loadPdfBitmap() async {
    final path = widget.pdfImageUrl;
    if (!widget.showPdfOverlay || path == null || path.isEmpty) {
      if (_pdfBitmap != null) {
        setState(() => _pdfBitmap = null);
      }
      return;
    }

    final bitmap = await loadLayoutGroundOverlayBitmap(path);
    if (!mounted) return;
    setState(() {
      _pdfBitmap = bitmap;
      _overlayEpoch++;
    });
  }

  Set<gmaps.GroundOverlay> _buildGroundOverlays() {
    if (!widget.showPdfOverlay ||
        widget.pdfImageUrl == null ||
        widget.pdfBounds == null ||
        _pdfBitmap == null) {
      return {};
    }

    final bounds = widget.pdfBounds!;
    return {
      gmaps.GroundOverlay.fromBounds(
        groundOverlayId: const gmaps.GroundOverlayId('hlo_layout_overlay'),
        image: _pdfBitmap!,
        bounds: imageBoundsToGoogle(bounds),
        transparency: (1 - widget.pdfOpacity.clamp(0.0, 1.0)).clamp(0.0, 1.0),
        bearing: SatelliteAlignMath.normalizeMapBearing(bounds.rotation),
        clickable: false,
        zIndex: 1,
      ),
    };
  }

  Future<void> _fitCamera() async {
    final controller = _controller;
    if (controller == null || widget.boundary.length < 2) return;

    final points = boundaryToGoogle(widget.boundary);
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

  Set<gmaps.Marker> _buildMarkers() {
    final markers = <gmaps.Marker>{};
    final ring = widget.boundary;
    if (ring.isEmpty) return markers;

    final canDrag = widget.enableCornerDrag && widget.lockedCount < 2;

    for (var i = 0; i < ring.length; i++) {
      final isLocked1 = widget.lockedCorner1Index == i;
      final isLocked2 = widget.lockedCorner2Index == i;
      final isLocked = isLocked1 || isLocked2;
      final isSelected = widget.selectedCornerIndex == i;
      final draggable = canDrag && isSelected && !isLocked;

      double hue;
      if (isLocked) {
        hue = gmaps.BitmapDescriptor.hueGreen;
      } else if (isSelected) {
        hue = gmaps.BitmapDescriptor.hueOrange;
      } else {
        hue = gmaps.BitmapDescriptor.hueAzure;
      }

      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('corner_$i'),
          position: gmaps.LatLng(ring[i].lat, ring[i].lng),
          draggable: draggable,
          zIndexInt: isSelected ? 3 : (isLocked ? 2 : 1),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: gmaps.InfoWindow(
            title: isLocked
                ? 'Corner ${i + 1} locked'
                : isSelected
                    ? 'Corner ${i + 1} — use arrows'
                    : 'Corner ${i + 1}',
          ),
          onTap: isLocked ? null : () => widget.onCornerSelected(i),
          onDrag: draggable
              ? (pos) => widget.onCornerDragged(i, LatLng(pos.latitude, pos.longitude))
              : null,
          onDragEnd: draggable
              ? (pos) => widget.onCornerDragged(i, LatLng(pos.latitude, pos.longitude))
              : null,
        ),
      );
    }

    if (widget.showRegionPins) {
      for (final r in widget.regions) {
        if (!r.visible) continue;
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('region_${r.id}'),
            position: toGoogleLatLng(r.point),
            zIndexInt: 0,
            icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              r.confirmed ? gmaps.BitmapDescriptor.hueGreen : gmaps.BitmapDescriptor.hueAzure,
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final ring = boundaryToGoogle(widget.boundary);
    final initial = ring.isNotEmpty ? ring.first : const gmaps.LatLng(10, 76);

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
