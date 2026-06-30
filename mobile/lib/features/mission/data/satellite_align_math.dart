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
    // Google ground overlay bearing is clockwise from north.
    final rad = -bounds.rotation * math.pi / 180;
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

  /// Prefer UV ring + overlay bounds so the GPS ring stays locked to the PDF after fine tune.
  static List<GpsPoint> gpsBoundaryForOverlay(
    ImageBounds? bounds,
    List<({double x, double y})> uvRing, {
    List<GpsPoint> fallback = const [],
  }) {
    if (bounds != null && uvRing.length >= 3) {
      return gpsBoundaryFromUvRing(bounds, uvRing);
    }
    return fallback;
  }

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

  static const _cornerUvs = <(double u, double v)>[(0, 0), (1, 0), (1, 1), (0, 1)];
  static const _edgeUvs = <(double u, double v)>[(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)];
  static const _edgeBaseBearingDeg = [0.0, 90.0, 180.0, 270.0];

  /// PDF overlay corner handles (NW, NE, SE, SW) in GPS.
  static List<LatLng> overlayCornerPositions(ImageBounds bounds) => [
        for (final uv in _cornerUvs) imageUvToLatLngRotated(uv.$1, uv.$2, bounds),
      ];

  /// PDF overlay edge midpoints (N, E, S, W) in GPS — used for rotation.
  static List<LatLng> overlayEdgePositions(ImageBounds bounds) => [
        for (final uv in _edgeUvs) imageUvToLatLngRotated(uv.$1, uv.$2, bounds),
      ];

  static ({double north, double east}) _latLngToLocalM(LatLng center, LatLng point) {
    final dNorth = (point.latitude - center.latitude) * _mPerDegLat;
    final mPerDegLng = _mPerDegLat * math.cos(center.latitude * math.pi / 180);
    final dEast = (point.longitude - center.longitude) * mPerDegLng;
    return (north: dNorth, east: dEast);
  }

  static double bearingDegrees(LatLng from, LatLng to) {
    final local = _latLngToLocalM(from, to);
    return normalizeMapBearing(math.atan2(local.east, local.north) * 180 / math.pi);
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    final dNorth = (b.latitude - a.latitude) * _mPerDegLat;
    final mPerDegLng = _mPerDegLat * math.cos(a.latitude * math.pi / 180);
    final dEast = (b.longitude - a.longitude) * mPerDegLng;
    return math.sqrt(dNorth * dNorth + dEast * dEast);
  }

  static LatLng _pointFromAnchor(LatLng anchor, LatLng point, double scale) {
    return LatLng(
      anchor.latitude + (point.latitude - anchor.latitude) * scale,
      anchor.longitude + (point.longitude - anchor.longitude) * scale,
    );
  }

  /// Project [query] onto the ray from [anchor] through [through].
  static LatLng _projectOntoRay(LatLng anchor, LatLng through, LatLng query) {
    final dir = _latLngToLocalM(anchor, through);
    final q = _latLngToLocalM(anchor, query);
    final len2 = dir.north * dir.north + dir.east * dir.east;
    if (len2 < 1e-4) return through;
    final t = (q.north * dir.north + q.east * dir.east) / len2;
    final mPerDegLng = _mPerDegLat * math.cos(anchor.latitude * math.pi / 180);
    return LatLng(
      anchor.latitude + (dir.north * t) / _mPerDegLat,
      anchor.longitude + (dir.east * t) / mPerDegLng,
    );
  }

  /// Uniform resize from a corner drag — opposite corner stays fixed, no stretch.
  static ImageBounds resizeFromCornerDrag(ImageBounds bounds, int cornerIndex, LatLng newCorner) {
    final oppIdx = (cornerIndex + 2) % 4;
    final opp = imageUvToLatLngRotated(_cornerUvs[oppIdx].$1, _cornerUvs[oppIdx].$2, bounds);
    final origCorner = imageUvToLatLngRotated(
      _cornerUvs[cornerIndex].$1,
      _cornerUvs[cornerIndex].$2,
      bounds,
    );

    final projected = _projectOntoRay(opp, origCorner, newCorner);
    final origDist = _distanceMeters(opp, origCorner);
    if (origDist < 1) return bounds;

    final scale = (_distanceMeters(opp, projected) / origDist).clamp(0.05, 20.0);

    final center = bounds.center;
    final newCenter = _pointFromAnchor(opp, center, scale);
    final halfLat = ((bounds.north - bounds.south) / 2) * scale;
    final halfLng = ((bounds.east - bounds.west) / 2) * scale;

    return ImageBounds(
      north: newCenter.latitude + halfLat,
      south: newCenter.latitude - halfLat,
      east: newCenter.longitude + halfLng,
      west: newCenter.longitude - halfLng,
      rotation: bounds.rotation,
    );
  }

  static const double fineTuneMoveDamp = 1.0;
  static const double fineTuneResizeDamp = 0.82;
  static const double fineTuneRotateDamp = 0.55;

  static double bearingDeltaDegrees(LatLng from, LatLng start, LatLng end) {
    var delta = bearingDegrees(from, end) - bearingDegrees(from, start);
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }

  /// Pan overlay by finger delta from drag start (stable — always uses [base]).
  static ImageBounds fineTuneShift(ImageBounds base, LatLng startFinger, LatLng endFinger) {
    final dLat = (endFinger.latitude - startFinger.latitude) * fineTuneMoveDamp;
    final dLng = (endFinger.longitude - startFinger.longitude) * fineTuneMoveDamp;
    return base.copyWith(
      north: base.north + dLat,
      south: base.south + dLat,
      east: base.east + dLng,
      west: base.west + dLng,
    );
  }

  /// Rotate overlay by bearing change since drag start (stable — always uses [base]).
  static ImageBounds fineTuneRotate(
    ImageBounds base,
    LatLng startFinger,
    LatLng endFinger,
  ) {
    final center = base.center;
    final delta = bearingDeltaDegrees(center, startFinger, endFinger) * fineTuneRotateDamp;
    return base.copyWith(rotation: normalizeMapBearing(base.rotation + delta));
  }

  /// Uniform resize from corner using finger delta since drag start (stable — always uses [base]).
  static ImageBounds fineTuneResizeCorner(
    ImageBounds base,
    int cornerIndex,
    LatLng startFinger,
    LatLng endFinger,
  ) {
    final startCorner = imageUvToLatLngRotated(
      _cornerUvs[cornerIndex].$1,
      _cornerUvs[cornerIndex].$2,
      base,
    );
    final dLat = (endFinger.latitude - startFinger.latitude) * fineTuneResizeDamp;
    final dLng = (endFinger.longitude - startFinger.longitude) * fineTuneResizeDamp;
    final newCorner = LatLng(startCorner.latitude + dLat, startCorner.longitude + dLng);
    return resizeFromCornerDrag(base, cornerIndex, newCorner);
  }

  /// Rotate overlay so the dragged edge midpoint follows [dragPosition].
  static ImageBounds rotateFromEdgeDrag(ImageBounds bounds, int edgeIndex, LatLng dragPosition) {
    final center = bounds.center;
    final bearing = bearingDegrees(center, dragPosition);
    final newRotation = normalizeMapBearing(bearing - _edgeBaseBearingDeg[edgeIndex]);
    return bounds.copyWith(rotation: newRotation);
  }

  /// Move overlay so its center sits at [newCenter].
  static ImageBounds shiftBoundsToCenter(ImageBounds bounds, LatLng newCenter) {
    final old = bounds.center;
    final dLat = newCenter.latitude - old.latitude;
    final dLng = newCenter.longitude - old.longitude;
    return bounds.copyWith(
      north: bounds.north + dLat,
      south: bounds.south + dLat,
      east: bounds.east + dLng,
      west: bounds.west + dLng,
    );
  }

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
