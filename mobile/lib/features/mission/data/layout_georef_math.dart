import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class GeorefControlPoint {
  GeorefControlPoint({
    required this.id,
    required this.label,
    required this.sketchX,
    required this.sketchY,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String label;
  final double sketchX;
  final double sketchY;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'sketchX': sketchX,
        'sketchY': sketchY,
        'lat': lat,
        'lng': lng,
      };

  factory GeorefControlPoint.fromJson(Map<String, dynamic> json) => GeorefControlPoint(
        id: json['id'] as String,
        label: json['label'] as String,
        sketchX: (json['sketchX'] as num).toDouble(),
        sketchY: (json['sketchY'] as num).toDouble(),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}

class LayoutGeorefMath {
  static List<double> computeAffine(List<GeorefControlPoint> points) {
    if (points.length < 3) throw StateError('Need 3+ control points');
    final latCoeffs = _solvePlane(points.map((p) => (x: p.sketchX, y: p.sketchY, v: p.lat)).toList());
    final lngCoeffs = _solvePlane(points.map((p) => (x: p.sketchX, y: p.sketchY, v: p.lng)).toList());
    return [...latCoeffs, ...lngCoeffs];
  }

  static LatLng applyAffine(List<double> m, double x, double y) {
    return LatLng(m[0] * x + m[1] * y + m[2], m[3] * x + m[4] * y + m[5]);
  }

  static double rmsErrorMeters(List<double> m, List<GeorefControlPoint> points) {
    const dist = Distance();
    var sum = 0.0;
    for (final p in points) {
      final pred = applyAffine(m, p.sketchX, p.sketchY);
      final err = dist(LatLng(p.lat, p.lng), pred);
      sum += err * err;
    }
    return math.sqrt(sum / points.length);
  }

  static String alignmentLabel(double rms) {
    if (rms < 10) return 'Excellent';
    if (rms < 25) return 'Good';
    return 'Needs Review';
  }

  /// Affine from 3+ points; 2 points use axis-aligned scale + shift.
  static List<double> computeAffineMinPoints(List<GeorefControlPoint> points) {
    if (points.length >= 3) return computeAffine(points);
    if (points.length == 2) return _affineFromTwoPoints(points[0], points[1]);
    throw StateError('Need 2+ control points');
  }

  static List<double> _affineFromTwoPoints(GeorefControlPoint p1, GeorefControlPoint p2) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = mPerDegLat * math.cos(p1.lat * math.pi / 180);

    final du = p2.sketchX - p1.sketchX;
    final dv = p2.sketchY - p1.sketchY;
    final uvLen = math.sqrt(du * du + dv * dv);
    if (uvLen < 1e-5) throw StateError('Control points too close in map space');

    final dEast = (p2.lng - p1.lng) * mPerDegLng;
    final dNorth = (p2.lat - p1.lat) * mPerDegLat;
    final gpsLen = math.sqrt(dEast * dEast + dNorth * dNorth);
    if (gpsLen < 1) throw StateError('Control points too close on ground');

    final s = gpsLen / uvLen;
    final sinT = (du * dNorth - dv * dEast) / (uvLen * gpsLen);
    final cosT = (du * dEast + dv * dNorth) / (uvLen * gpsLen);

    final m0 = s * (-sinT) / mPerDegLat;
    final m1 = s * cosT / mPerDegLat;
    final m2 = p1.lat - m0 * p1.sketchX - m1 * p1.sketchY;
    final m3 = s * cosT / mPerDegLng;
    final m4 = s * sinT / mPerDegLng;
    final m5 = p1.lng - m3 * p1.sketchX - m4 * p1.sketchY;
    return [m0, m1, m2, m3, m4, m5];
  }

  static List<double> _solvePlane(List<({double x, double y, double v})> samples) {
    double sxx = 0, syy = 0, sxy = 0, sx = 0, sy = 0, n = 0, svx = 0, svy = 0, sv = 0;
    for (final p in samples) {
      sxx += p.x * p.x;
      syy += p.y * p.y;
      sxy += p.x * p.y;
      sx += p.x;
      sy += p.y;
      n += 1;
      svx += p.x * p.v;
      svy += p.y * p.v;
      sv += p.v;
    }
    return _solve3([
      [sxx, sxy, sx],
      [sxy, syy, sy],
      [sx, sy, n],
    ], [svx, svy, sv]);
  }

  static List<double> _solve3(List<List<double>> a, List<double> b) {
    final aug = [for (var i = 0; i < 3; i++) [...a[i], b[i]]];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var row = col + 1; row < 3; row++) {
        if (aug[row][col].abs() > aug[pivot][col].abs()) pivot = row;
      }
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;
      final div = aug[col][col] == 0 ? 1e-12 : aug[col][col];
      for (var j = col; j <= 3; j++) aug[col][j] /= div;
      for (var row = 0; row < 3; row++) {
        if (row == col) continue;
        final f = aug[row][col];
        for (var j = col; j <= 3; j++) aug[row][j] -= f * aug[col][j];
      }
    }
    return [aug[0][3], aug[1][3], aug[2][3]];
  }
}
