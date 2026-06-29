import 'package:flutter/material.dart';import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/mission_map_helpers.dart';
import '../data/mission_map_style.dart';
import '../models/layout_georef_models.dart';

/// Satellite-first map canvas — see docs/MISSION_MAP_UX.md
enum MissionMapMode { prediction, mission }

class MapRegionMarker {
  const MapRegionMarker({
    required this.id,
    required this.point,
    this.confirmed = false,
    this.visible = true,
  });

  final String id;
  final LatLng point;
  final bool confirmed;
  final bool visible;
}

class MissionSatelliteMap extends StatelessWidget {
  const MissionSatelliteMap({
    required this.center,
    required this.boundary,
    this.regions = const [],
    this.userPosition,
    this.mode = MissionMapMode.prediction,
    this.boundaryDrawProgress = 1.0,
    this.zoom = 17,
    this.showPdfOverlay = false,
    this.pdfImageUrl,
    this.pdfBounds,
    this.pdfOpacity = 0.45,
    this.showRegionPins = false,
    super.key,
  });

  static const satelliteTiles =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  final LatLng center;
  final List<GpsPoint> boundary;
  final List<MapRegionMarker> regions;
  final LatLng? userPosition;
  final MissionMapMode mode;
  final double boundaryDrawProgress;
  final double zoom;
  final bool showPdfOverlay;
  final String? pdfImageUrl;
  final ImageBounds? pdfBounds;
  final double pdfOpacity;
  final bool showRegionPins;

  static LatLng? boundsCenter(List<GpsPoint> ring) {
    if (ring.isEmpty) return null;
    var lat = 0.0;
    var lng = 0.0;
    for (final p in ring) {
      lat += p.lat;
      lng += p.lng;
    }
    return LatLng(lat / ring.length, lng / ring.length);
  }

  static double? boundsZoom(List<GpsPoint> ring) {
    if (ring.length < 2) return 17;
    var minLat = ring.first.lat;
    var maxLat = ring.first.lat;
    var minLng = ring.first.lng;
    var maxLng = ring.first.lng;
    for (final p in ring) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    final span = (maxLat - minLat).abs().clamp(0.0005, 0.08);
    if (span > 0.04) return 14;
    if (span > 0.02) return 15;
    if (span > 0.01) return 16;
    return 17;
  }

  List<LatLng> _partialBoundary() {
    if (boundary.length < 2) return [];
    final closed = [...boundary.map((p) => LatLng(p.lat, p.lng))];
    if (closed.first != closed.last) closed.add(closed.first);
    final total = closed.length;
    final take = (total * boundaryDrawProgress.clamp(0, 1)).ceil().clamp(2, total);
    return closed.sublist(0, take);
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = boundsCenter(boundary) ?? center;
    final mapZoom = boundsZoom(boundary) ?? zoom;
    final partial = _partialBoundary();
    final boundaryComplete = boundaryDrawProgress >= 0.99;

    const boundaryColor = MissionMapStyle.boundaryColor;
    final regionHypothesis = mode == MissionMapMode.prediction
        ? const Color(0xFF64B5F6)
        : const Color(0xFF9E9E9E);
    const regionConfirmed = Color(0xFF00E676);

    final layers = <Widget>[
      TileLayer(urlTemplate: satelliteTiles, userAgentPackageName: 'com.spatialverify.app'),
    ];

    if (showPdfOverlay && pdfImageUrl != null && pdfBounds != null) {
      final b = pdfBounds!;
      layers.add(OverlayImageLayer(overlayImages: [
        OverlayImage(
          bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)),
          opacity: pdfOpacity,
          imageProvider: pdfOverlayImageProvider(pdfImageUrl!),
        ),
      ],),);
    }

    if (partial.length >= 2) {
      layers.add(PolylineLayer(polylines: [
        Polyline(
          points: partial,
          color: boundaryColor,
          strokeWidth: MissionMapStyle.boundaryWidth,
          pattern: MissionMapStyle.flutterBoundaryPattern(complete: boundaryComplete),
        ),
      ],),);
    }

    final markers = <Marker>[];
    if (showRegionPins) {
      for (final r in regions) {
      if (!r.visible) continue;
      final color = r.confirmed ? regionConfirmed : regionHypothesis;
      markers.add(Marker(
        point: r.point,
        width: 28,
        height: 28,
        child: AnimatedOpacity(
          opacity: r.visible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
            child: r.confirmed
                ? const Icon(Icons.check, size: 14, color: Colors.black)
                : null,
          ),
        ),
      ),);
      }
    }

    if (userPosition != null) {
      markers.add(Marker(
        point: userPosition!,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
        ),
      ),);
    }

    if (markers.isNotEmpty) {
      layers.add(MarkerLayer(markers: markers));
    }

    return FlutterMap(
      options: MapOptions(initialCenter: mapCenter, initialZoom: mapZoom, interactionOptions: const InteractionOptions()),
      children: layers,
    );
  }
}

/// Parse observation region markers from mission intelligence JSON.
List<MapRegionMarker> regionsFromIntelligence(Map<String, dynamic>? raw) => const [];
