import 'dart:math' as math;

/// Geo + serpentine + gap detection — runs entirely on-device for offline HLB state.
class HlbGeoEngine {
  HlbGeoEngine._();

  static double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static MapBounds computeBounds(List<GpsCoord> points) {
    if (points.isEmpty) return const MapBounds(0, 1, 0, 1);
    return MapBounds(
      points.map((p) => p.latitude).reduce(math.min),
      points.map((p) => p.latitude).reduce(math.max),
      points.map((p) => p.longitude).reduce(math.min),
      points.map((p) => p.longitude).reduce(math.max),
    );
  }

  static MapPoint projectToMap(double lat, double lng, MapBounds bounds) {
    final latSpan = math.max(bounds.maxLat - bounds.minLat, 0.0001);
    final lngSpan = math.max(bounds.maxLng - bounds.minLng, 0.0001);
    return MapPoint(
      (lng - bounds.minLng) / lngSpan,
      (bounds.maxLat - lat) / latSpan,
    );
  }

  static int estimatePathCoveragePercent(List<GpsCoord> breadcrumbs, MapBounds bounds, {int gridSize = 8}) {
    if (breadcrumbs.isEmpty) return 0;
    final visited = <String>{};
    for (final b in breadcrumbs) {
      final p = projectToMap(b.latitude, b.longitude, bounds);
      if (p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1) {
        visited.add('${math.min(gridSize - 1, (p.x * gridSize).floor())},${math.min(gridSize - 1, (p.y * gridSize).floor())}');
      }
    }
    return ((visited.length / (gridSize * gridSize)) * 100).round();
  }

  static double pathWalkedMeters(List<GpsCoord> breadcrumbs) {
    var total = 0.0;
    for (var i = 1; i < breadcrumbs.length; i++) {
      total += haversineMeters(
        breadcrumbs[i - 1].latitude,
        breadcrumbs[i - 1].longitude,
        breadcrumbs[i].latitude,
        breadcrumbs[i].longitude,
      );
    }
    return total;
  }

  static String formatCn(int n) => 'CN-${n.toString().padLeft(3, '0')}';

  static List<GpsBuilding> serpentineOrder(List<GpsBuilding> points, {double rowWidthMeters = 40}) {
    if (points.length <= 1) return List.from(points);
    final lats = points.map((p) => p.latitude);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final latSpan = math.max(maxLat - minLat, 0.00001);
    final rows = math.max(1, (latSpan * 111320 / rowWidthMeters).ceil());

    final withRow = points.map((p) {
      final row = math.min(rows - 1, ((maxLat - p.latitude) / latSpan * rows).floor());
      return (p, row);
    }).toList();

    withRow.sort((a, b) {
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      final odd = a.$2 % 2 == 0;
      return odd ? a.$1.longitude.compareTo(b.$1.longitude) : b.$1.longitude.compareTo(a.$1.longitude);
    });
    return withRow.map((e) => e.$1).toList();
  }

  static int suggestSerpentineNumber(double lat, double lng, List<GpsBuilding> existing) {
    if (existing.isEmpty) return 1;
    final combined = serpentineOrder([...existing, GpsBuilding('new', lat, lng, null)]);
    final idx = combined.indexWhere((p) => p.id == 'new');
    return idx >= 0 ? idx + 1 : existing.length + 1;
  }

  static double? bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2 - lng1) * math.pi / 180;
    final lat1r = lat1 * math.pi / 180;
    final lat2r = lat2 * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2r);
    final x = math.cos(lat1r) * math.sin(lat2r) - math.sin(lat1r) * math.cos(lat2r) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  static bool boundaryClosed(List<GpsCoord> vertices) {
    if (vertices.length < 4) return false;
    final first = vertices.first;
    final last = vertices.last;
    return haversineMeters(first.latitude, first.longitude, last.latitude, last.longitude) <= 50;
  }

  static int nearbyBuildings(double lat, double lng, List<GpsBuilding> buildings, double radius) {
    return buildings.where((b) => haversineMeters(lat, lng, b.latitude, b.longitude) <= radius).length;
  }

  static List<({double lat, double lng})> findUnrecordedClusters(
    List<GpsCoord> breadcrumbs,
    List<GpsBuilding> buildings, {
    double minDistance = 80,
  }) {
    if (buildings.isEmpty || breadcrumbs.length < 5) return [];
    final clusters = <({double lat, double lng})>[];
    const window = 5;
    for (var i = 0; i < breadcrumbs.length; i += window) {
      final slice = breadcrumbs.skip(i).take(window).toList();
      if (slice.isEmpty) continue;
      final lat = slice.map((p) => p.latitude).reduce((a, b) => a + b) / slice.length;
      final lng = slice.map((p) => p.longitude).reduce((a, b) => a + b) / slice.length;
      final near = buildings.any((b) => haversineMeters(lat, lng, b.latitude, b.longitude) < minDistance);
      if (!near) clusters.add((lat: lat, lng: lng));
    }
    return clusters.take(5).toList();
  }

  static List<({double lat, double lng, int cx, int cy})> findUnvisitedGridCells(
    List<GpsCoord> breadcrumbs,
    MapBounds bounds, {
    int gridSize = 8,
  }) {
    if (breadcrumbs.isEmpty) return [];
    final visited = <String>{};
    for (final b in breadcrumbs) {
      final p = projectToMap(b.latitude, b.longitude, bounds);
      if (p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1) {
        visited.add('${math.min(gridSize - 1, (p.x * gridSize).floor())},${math.min(gridSize - 1, (p.y * gridSize).floor())}');
      }
    }
    final latSpan = math.max(bounds.maxLat - bounds.minLat, 0.0001);
    final lngSpan = math.max(bounds.maxLng - bounds.minLng, 0.0001);
    final cells = <({double lat, double lng, int cx, int cy})>[];
    for (var cx = 0; cx < gridSize; cx++) {
      for (var cy = 0; cy < gridSize; cy++) {
        if (visited.contains('$cx,$cy')) continue;
        final x = (cx + 0.5) / gridSize;
        final y = (cy + 0.5) / gridSize;
        cells.add((
          lat: bounds.maxLat - y * latSpan,
          lng: bounds.minLng + x * lngSpan,
          cx: cx,
          cy: cy,
        ));
      }
    }
    return cells.take(12).toList();
  }

  static String gapFingerprint(String type, String reason, double? lat, double? lng) {
    if (lat != null && lng != null) {
      return '$type:${lat.toStringAsFixed(5)}:${lng.toStringAsFixed(5)}';
    }
    return '$type:$reason';
  }

  /// Ray-casting point-in-polygon for official HLB boundary rings.
  static bool pointInPolygon(double lat, double lng, List<({double lat, double lng})> ring) {
    if (ring.length < 3) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final yi = ring[i].lat;
      final xi = ring[i].lng;
      final yj = ring[j].lat;
      final xj = ring[j].lng;
      final intersect = yi > lat != yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi + 0.0) + xi;
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static List<GpsCoord> filterInsidePolygon(List<GpsCoord> points, List<({double lat, double lng})> ring) {
    if (ring.isEmpty) return points;
    return points.where((p) => pointInPolygon(p.latitude, p.longitude, ring)).toList();
  }

  static ({double lat, double lng}) computeNorthWestStart(List<({double lat, double lng})> ring) {
    if (ring.isEmpty) return (lat: 0, lng: 0);
    var best = ring.first;
    for (final p in ring) {
      if (p.lat > best.lat || (p.lat == best.lat && p.lng < best.lng)) best = p;
    }
    return best;
  }

  static int estimateCoverageInsidePolygon(
    List<GpsCoord> breadcrumbs,
    List<({double lat, double lng})> ring, {
    int gridSize = 8,
  }) {
    if (ring.isEmpty || breadcrumbs.isEmpty) return 0;
    final bounds = computeBounds(ring.map((p) => GpsCoord(p.lat, p.lng)).toList());
    final insideCrumbs = filterInsidePolygon(breadcrumbs, ring);
    if (insideCrumbs.isEmpty) return 0;

    var insideCells = 0;
    var totalCells = 0;
    final latSpan = math.max(bounds.maxLat - bounds.minLat, 0.0001);
    final lngSpan = math.max(bounds.maxLng - bounds.minLng, 0.0001);

    for (var cx = 0; cx < gridSize; cx++) {
      for (var cy = 0; cy < gridSize; cy++) {
        final x = (cx + 0.5) / gridSize;
        final y = (cy + 0.5) / gridSize;
        final lat = bounds.maxLat - y * latSpan;
        final lng = bounds.minLng + x * lngSpan;
        if (!pointInPolygon(lat, lng, ring)) continue;
        totalCells++;
        final visited = insideCrumbs.any((b) {
          final p = projectToMap(b.latitude, b.longitude, bounds);
          final cellX = math.min(gridSize - 1, (p.x * gridSize).floor());
          final cellY = math.min(gridSize - 1, (p.y * gridSize).floor());
          return cellX == cx && cellY == cy;
        });
        if (visited) insideCells++;
      }
    }
    if (totalCells == 0) return estimatePathCoveragePercent(insideCrumbs, bounds, gridSize: gridSize);
    return ((insideCells / totalCells) * 100).round();
  }

  static String cardinalLabel(double? bearing) {
    if (bearing == null) return '';
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = ((bearing + 22.5) % 360 / 45).floor();
    return dirs[idx];
  }
}

class GpsCoord {
  const GpsCoord(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class GpsBuilding {
  const GpsBuilding(this.id, this.latitude, this.longitude, this.buildingNumber);
  final String id;
  final double latitude;
  final double longitude;
  final int? buildingNumber;
}

class MapBounds {
  const MapBounds(this.minLat, this.maxLat, this.minLng, this.maxLng);
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}

class MapPoint {
  const MapPoint(this.x, this.y);
  final double x;
  final double y;
}
