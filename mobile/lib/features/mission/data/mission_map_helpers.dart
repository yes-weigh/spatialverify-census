import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/storage/mission_layout_storage.dart';

import '../models/layout_georef_models.dart';
import 'boundary_rigid_align_math.dart';
import 'pdf_layout_mask.dart';
import 'satellite_align_math.dart';

/// Local file path or http(s) URL for HLO layout overlay on flutter_map.
ImageProvider pdfOverlayImageProvider(String urlOrPath) {
  final lower = urlOrPath.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return CachedNetworkImageProvider(urlOrPath);
  }
  return FileImage(File(urlOrPath));
}
/// NW entry corner of an HLB ring (official census start convention).
gmaps.LatLng missionEntryPoint(List<GpsPoint> boundary) {
  if (boundary.isEmpty) return const gmaps.LatLng(0, 0);
  var maxLat = boundary.first.lat;
  var minLng = boundary.first.lng;
  for (final p in boundary) {
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
  }
  return gmaps.LatLng(maxLat, minLng);
}

gmaps.LatLng toGoogleLatLng(LatLng point) => gmaps.LatLng(point.latitude, point.longitude);

gmaps.LatLng? gpsToGoogle(GpsPoint? point) =>
    point == null ? null : gmaps.LatLng(point.lat, point.lng);

List<gmaps.LatLng> boundaryToGoogle(List<GpsPoint> boundary) =>
    boundary.map((p) => gmaps.LatLng(p.lat, p.lng)).toList();

gmaps.LatLng? boundaryCenterGoogle(List<GpsPoint> boundary) {
  if (boundary.isEmpty) return null;
  var lat = 0.0;
  var lng = 0.0;
  for (final p in boundary) {
    lat += p.lat;
    lng += p.lng;
  }
  return gmaps.LatLng(lat / boundary.length, lng / boundary.length);
}

gmaps.LatLngBounds imageBoundsToGoogle(ImageBounds bounds) => gmaps.LatLngBounds(
      southwest: gmaps.LatLng(bounds.south, bounds.west),
      northeast: gmaps.LatLng(bounds.north, bounds.east),
    );

ImageBounds transformImageBounds(ImageBounds bounds, RigidBoundaryTransform transform) {
  final corners = [
    GpsPoint(bounds.north, bounds.west),
    GpsPoint(bounds.north, bounds.east),
    GpsPoint(bounds.south, bounds.west),
    GpsPoint(bounds.south, bounds.east),
  ];
  final transformed = [
    for (final p in corners) BoundaryRigidAlignMath.applyTransform(p, transform),
  ];

  var north = transformed.first.lat;
  var south = transformed.first.lat;
  var east = transformed.first.lng;
  var west = transformed.first.lng;
  for (final p in transformed) {
    if (p.lat > north) north = p.lat;
    if (p.lat < south) south = p.lat;
    if (p.lng > east) east = p.lng;
    if (p.lng < west) west = p.lng;
  }

  return ImageBounds(
    north: north,
    south: south,
    east: east,
    west: west,
    rotation: SatelliteAlignMath.normalizeMapBearing(
      bounds.rotation + transform.rotationRad * 180 / 3.141592653589793,
    ),
  );
}

Future<gmaps.BytesMapBitmap?> loadLayoutGroundOverlayBitmap(
  String urlOrPath, {
  bool maskOutsideUvRing = false,
  List<({double x, double y})> uvRing = const [],
}) async {
  try {
    final lower = urlOrPath.toLowerCase();
    Uint8List? bytes;
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final response = await Dio().get<List<int>>(
        urlOrPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      bytes = Uint8List.fromList(data);
    } else {
      bytes = await readMissionLayoutBytes(urlOrPath);
    }
    if (bytes == null || bytes.isEmpty) return null;
    if (maskOutsideUvRing && uvRing.length >= 3) {
      bytes = maskLayoutPngOutsideBoundary(bytes, uvRing);
    }
    return gmaps.BytesMapBitmap(
      bytes,
      bitmapScaling: gmaps.MapBitmapScaling.none,
    );
  } catch (_) {
    return null;
  }
}

/// App-lifetime guard: pan map to GPS only once at launch.
class MissionMapCameraSession {
  MissionMapCameraSession._();

  static var hasAutoCenteredOnUser = false;
}
