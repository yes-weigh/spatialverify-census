import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/layout_georef_models.dart';
import '../models/pdf_georef_models.dart';
import 'layout_georef_math.dart';

/// Image overlay alignment — officer satellite map corners mapped to GPS bounds.
class ImageBounds {
  ImageBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    this.rotation = 0,
  });

  final double north;
  final double south;
  final double east;
  final double west;
  final double rotation;

  LatLng get center => LatLng((north + south) / 2, (east + west) / 2);

  Map<String, dynamic> toJson() => {
        'north': north,
        'south': south,
        'east': east,
        'west': west,
        if (rotation != 0) 'rotation': rotation,
      };

  factory ImageBounds.fromJson(Map<String, dynamic> json) => ImageBounds(
        north: (json['north'] as num).toDouble(),
        south: (json['south'] as num).toDouble(),
        east: (json['east'] as num).toDouble(),
        west: (json['west'] as num).toDouble(),
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );

  ImageBounds copyWith({
    double? north,
    double? south,
    double? east,
    double? west,
    double? rotation,
  }) =>
      ImageBounds(
        north: north ?? this.north,
        south: south ?? this.south,
        east: east ?? this.east,
        west: west ?? this.west,
        rotation: rotation ?? this.rotation,
      );
}

class SatelliteAlignMath {
  static const _mPerDegLat = 111320.0;

  /// Google Maps ground overlays require bearing in \[0, 360\].
  static double normalizeMapBearing(double degrees) {
    var b = degrees % 360.0;
    if (b < 0) b += 360.0;
    return b;
  }

  static LatLng imageUvToLatLng(double u, double v, ImageBounds bounds) {
    final lat = bounds.south + (1 - v) * (bounds.north - bounds.south);
    final lng = bounds.west + u * (bounds.east - bounds.west);
    return LatLng(lat, lng);
  }

  /// UV → GPS including [ImageBounds.rotation] (matches Google ground overlay bearing).
  static LatLng imageUvToLatLngRotated(double u, double v, ImageBounds bounds) {
    final unrotated = imageUvToLatLng(u, v, bounds);
    if (bounds.rotation.abs() < 0.001) return unrotated;

    final center = bounds.center;
    final mPerDegLng = _mPerDegLat * math.cos(center.latitude * math.pi / 180);
    final dx = (unrotated.longitude - center.longitude) * mPerDegLng;
    final dy = (unrotated.latitude - center.latitude) * _mPerDegLat;
    final rad = bounds.rotation * math.pi / 180;
    final cosR = math.cos(rad);
    final sinR = math.sin(rad);
    final rotDx = dx * cosR - dy * sinR;
    final rotDy = dx * sinR + dy * cosR;
    return LatLng(
      center.latitude + rotDy / _mPerDegLat,
      center.longitude + rotDx / mPerDegLng,
    );
  }

  static List<GpsPoint> gpsBoundaryFromUvRing(
    ImageBounds bounds,
    List<({double x, double y})> uvRing,
  ) =>
      [
        for (final p in uvRing)
          () {
            final ll = imageUvToLatLngRotated(p.x, p.y, bounds);
            return GpsPoint(ll.latitude, ll.longitude);
          }(),
      ];

  static ImageBounds boundsFromCenter(double centerLat, double centerLng, double widthM, double heightM) {
    final latSpan = heightM / _mPerDegLat;
    final lngSpan = widthM / (_mPerDegLat * math.cos(centerLat * math.pi / 180));
    return ImageBounds(
      north: centerLat + latSpan / 2,
      south: centerLat - latSpan / 2,
      east: centerLng + lngSpan / 2,
      west: centerLng - lngSpan / 2,
    );
  }

  static ImageBounds shiftBounds(ImageBounds bounds, double dNorthM, double dEastM) {
    final center = bounds.center;
    final dLat = dNorthM / _mPerDegLat;
    final dLng = dEastM / (_mPerDegLat * math.cos(center.latitude * math.pi / 180));
    return bounds.copyWith(
      north: bounds.north + dLat,
      south: bounds.south + dLat,
      east: bounds.east + dLng,
      west: bounds.west + dLng,
    );
  }

  static ImageBounds scaleBounds(ImageBounds bounds, double factor) {
    final c = bounds.center;
    final halfLat = ((bounds.north - bounds.south) / 2) * factor;
    final halfLng = ((bounds.east - bounds.west) / 2) * factor;
    return ImageBounds(
      north: c.latitude + halfLat,
      south: c.latitude - halfLat,
      east: c.longitude + halfLng,
      west: c.longitude - halfLng,
      rotation: bounds.rotation,
    );
  }

  static ImageBounds rotateBounds(ImageBounds bounds, double deltaDegrees) =>
      bounds.copyWith(rotation: normalizeMapBearing(bounds.rotation + deltaDegrees));

  /// Align detected boundary UV ring to enumerator GPS seed (mirrors backend mission-intelligence).
  static ({ImageBounds imageBounds, List<GpsPoint> gpsBoundary}) autoAlignFromBoundary(
    List<({double x, double y})> boundaryUv,
    double seedLat,
    double seedLng,
  ) {
    if (boundaryUv.isEmpty) {
      return (imageBounds: boundsFromCenter(seedLat, seedLng, 400, 400), gpsBoundary: []);
    }
    final cx = boundaryUv.map((p) => p.x).reduce((a, b) => a + b) / boundaryUv.length;
    final cy = boundaryUv.map((p) => p.y).reduce((a, b) => a + b) / boundaryUv.length;
    final minX = boundaryUv.map((p) => p.x).reduce(math.min);
    final maxX = boundaryUv.map((p) => p.x).reduce(math.max);
    final minY = boundaryUv.map((p) => p.y).reduce(math.min);
    final maxY = boundaryUv.map((p) => p.y).reduce(math.max);
    final spanX = math.max(maxX - minX, 0.12);
    final spanY = math.max(maxY - minY, 0.12);
    final maxSpan = math.max(spanX, spanY);
    final imageSizeM = (550 / maxSpan) * 1.25;
    final aspect = spanY / spanX;

    var bounds = boundsFromCenter(seedLat, seedLng, imageSizeM, imageSizeM * aspect);
    final centroid = imageUvToLatLng(cx, cy, bounds);
    final dNorthM = (seedLat - centroid.latitude) * _mPerDegLat;
    final dEastM = (seedLng - centroid.longitude) * _mPerDegLat * math.cos(seedLat * math.pi / 180);
    bounds = shiftBounds(bounds, dNorthM, dEastM);

    final gpsBoundary = boundaryUv
        .map((p) {
          final ll = imageUvToLatLng(p.x, p.y, bounds);
          return GpsPoint(ll.latitude, ll.longitude);
        })
        .toList();

    return (imageBounds: bounds, gpsBoundary: gpsBoundary);
  }

  /// Place boundary using confirmed map-label ↔ Google Places control points.
  static ({
    ImageBounds imageBounds,
    List<GpsPoint> gpsBoundary,
    List<double> affineMatrix,
    double rmsErrorMeters,
    String alignmentLabel,
  }) alignFromControlPoints(
    List<GeorefControlPoint> controlPoints,
    List<({double x, double y})> boundaryUv,
  ) {
    if (controlPoints.length < kMinGeorefMatchedPins) {
      throw ArgumentError('Need at least $kMinGeorefMatchedPins confirmed landmark matches');
    }

    final matrix = LayoutGeorefMath.computeAffineMinPoints(controlPoints);
    final gpsBoundary = boundaryUv
        .map((p) {
          final ll = LayoutGeorefMath.applyAffine(matrix, p.x, p.y);
          return GpsPoint(ll.latitude, ll.longitude);
        })
        .toList();

    final corners = [
      LayoutGeorefMath.applyAffine(matrix, 0, 0),
      LayoutGeorefMath.applyAffine(matrix, 1, 0),
      LayoutGeorefMath.applyAffine(matrix, 1, 1),
      LayoutGeorefMath.applyAffine(matrix, 0, 1),
    ];

    var north = corners.first.latitude;
    var south = corners.first.latitude;
    var east = corners.first.longitude;
    var west = corners.first.longitude;
    for (final c in corners) {
      north = math.max(north, c.latitude);
      south = math.min(south, c.latitude);
      east = math.max(east, c.longitude);
      west = math.min(west, c.longitude);
    }

    final rms = LayoutGeorefMath.rmsErrorMeters(matrix, controlPoints);
    return (
      imageBounds: ImageBounds(north: north, south: south, east: east, west: west),
      gpsBoundary: gpsBoundary,
      affineMatrix: matrix,
      rmsErrorMeters: rms,
      alignmentLabel: LayoutGeorefMath.alignmentLabel(rms),
    );
  }

  static double polygonAreaSqMeters(List<GpsPoint> ring) {
    if (ring.length < 3) return 0;
    var cLat = 0.0;
    var cLng = 0.0;
    for (final p in ring) {
      cLat += p.lat;
      cLng += p.lng;
    }
    cLat /= ring.length;
    cLng /= ring.length;
    final mPerDegLng = _mPerDegLat * math.cos(cLat * math.pi / 180);
    var area = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final j = (i + 1) % ring.length;
      final xi = (ring[i].lng - cLng) * mPerDegLng;
      final yi = (ring[i].lat - cLat) * _mPerDegLat;
      final xj = (ring[j].lng - cLng) * mPerDegLng;
      final yj = (ring[j].lat - cLat) * _mPerDegLat;
      area += xi * yj - xj * yi;
    }
    return area.abs() / 2;
  }

  static ({double lat, double lng}) northWestStartPoint(List<GpsPoint> ring) {
    if (ring.isEmpty) return (lat: 0, lng: 0);
    var best = ring.first;
    for (final p in ring) {
      if (p.lat > best.lat || (p.lat == best.lat && p.lng < best.lng)) best = p;
    }
    return (lat: best.lat, lng: best.lng);
  }
}
