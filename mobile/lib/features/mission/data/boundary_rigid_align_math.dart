import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/layout_georef_models.dart';

/// Rigid boundary correction — translate then rotate; shape is preserved.
class BoundaryRigidAlignMath {
  static const _mPerDegLat = 111320.0;

  static double _mPerDegLng(double lat) => _mPerDegLat * math.cos(lat * math.pi / 180);

  static ({double x, double y}) _toLocal(LatLng origin, GpsPoint p) {
    return (
      x: (p.lng - origin.longitude) * _mPerDegLng(origin.latitude),
      y: (p.lat - origin.latitude) * _mPerDegLat,
    );
  }

  static GpsPoint _fromLocal(LatLng origin, double x, double y) {
    return GpsPoint(
      origin.latitude + y / _mPerDegLat,
      origin.longitude + x / _mPerDegLng(origin.latitude),
    );
  }

  static GpsPoint _rotatePoint(GpsPoint p, LatLng pivot, double angleRad) {
    final local = _toLocal(pivot, p);
    final cos = math.cos(angleRad);
    final sin = math.sin(angleRad);
    return _fromLocal(
      pivot,
      local.x * cos - local.y * sin,
      local.x * sin + local.y * cos,
    );
  }

  /// Move the whole ring so [cornerIndex] lands on [target].
  static List<GpsPoint> translate(
    List<GpsPoint> ring,
    int cornerIndex,
    LatLng target,
  ) {
    if (ring.isEmpty || cornerIndex < 0 || cornerIndex >= ring.length) return ring;
    final anchor = ring[cornerIndex];
    final dLat = target.latitude - anchor.lat;
    final dLng = target.longitude - anchor.lng;
    return [
      for (final p in ring) GpsPoint(p.lat + dLat, p.lng + dLng),
    ];
  }

  /// Rotate the ring around [pivot] so [cornerIndex] lands on [target].
  static List<GpsPoint> rotateAround(
    List<GpsPoint> ring,
    LatLng pivot,
    int cornerIndex,
    LatLng target,
  ) {
    if (ring.isEmpty || cornerIndex < 0 || cornerIndex >= ring.length) return ring;

    final corner = GpsPoint(ring[cornerIndex].lat, ring[cornerIndex].lng);
    final localCorner = _toLocal(pivot, corner);
    final localTarget = _toLocal(pivot, GpsPoint(target.latitude, target.longitude));

    final angleCorner = math.atan2(localCorner.y, localCorner.x);
    final angleTarget = math.atan2(localTarget.y, localTarget.x);
    final angle = angleTarget - angleCorner;

    return [for (final p in ring) _rotatePoint(p, pivot, angle)];
  }

  static GpsPoint applyTransform(GpsPoint p, RigidBoundaryTransform transform) {
    var lat = p.lat;
    var lng = p.lng;
    if (transform.hasTranslation) {
      lat += transform.dLat;
      lng += transform.dLng;
    }
    if (transform.hasRotation && transform.rotationPivot != null) {
      return _rotatePoint(GpsPoint(lat, lng), transform.rotationPivot!, transform.rotationRad);
    }
    return GpsPoint(lat, lng);
  }

  static RigidBoundaryTransform transformFromLocks({
    required List<GpsPoint> baseRing,
    required int corner1Index,
    required LatLng corner1Target,
    int? corner2Index,
    LatLng? corner2Target,
  }) {
    final dLat = corner1Target.latitude - baseRing[corner1Index].lat;
    final dLng = corner1Target.longitude - baseRing[corner1Index].lng;

    if (corner2Index == null || corner2Target == null) {
      return RigidBoundaryTransform(dLat: dLat, dLng: dLng);
    }

    final afterTranslate = translate(baseRing, corner1Index, corner1Target);
    final pivot = corner1Target;
    final corner = GpsPoint(afterTranslate[corner2Index].lat, afterTranslate[corner2Index].lng);
    final localCorner = _toLocal(pivot, corner);
    final localTarget = _toLocal(pivot, GpsPoint(corner2Target.latitude, corner2Target.longitude));
    final angle = math.atan2(localTarget.y, localTarget.x) - math.atan2(localCorner.y, localCorner.x);

    return RigidBoundaryTransform(
      dLat: dLat,
      dLng: dLng,
      rotationPivot: pivot,
      rotationRad: angle,
    );
  }
}

class RigidBoundaryTransform {
  const RigidBoundaryTransform({
    this.dLat = 0,
    this.dLng = 0,
    this.rotationPivot,
    this.rotationRad = 0,
  });

  final double dLat;
  final double dLng;
  final LatLng? rotationPivot;
  final double rotationRad;

  bool get hasTranslation => dLat != 0 || dLng != 0;
  bool get hasRotation => rotationPivot != null && rotationRad != 0;

  bool get isComplete => hasTranslation && hasRotation;
}
