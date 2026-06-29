import 'dart:math' as math;

import '../data/hlb_geo_engine.dart';
import '../data/hlb_local_state.dart';

enum HeatmapCellState { unvisited, covered, partial, suspicious }

class HeatmapCell {
  const HeatmapCell({required this.x, required this.y, required this.state});
  final int x;
  final int y;
  final HeatmapCellState state;
}

class StreetSegment {
  const StreetSegment({
    required this.id,
    required this.name,
    required this.buildingsTotal,
    required this.buildingsConfirmed,
    required this.completionPercent,
    required this.points,
  });

  final String id;
  final String name;
  final int buildingsTotal;
  final int buildingsConfirmed;
  final int completionPercent;
  final List<({double lat, double lng})> points;
}

class DiscoveryReplayEvent {
  const DiscoveryReplayEvent({
    required this.time,
    required this.label,
    required this.type,
    this.latitude,
    this.longitude,
  });

  final DateTime time;
  final String label;
  final String type;
  final double? latitude;
  final double? longitude;
}

/// On-device discovery analytics — heatmap, streets, replay, ignored count.
class DiscoveryAnalytics {
  static const _gridSize = 8;

  static List<HeatmapCell> computeHeatmap(HlbLocalState state) {
    final ring = state.officialBoundaryRing;
    final bc = state.breadcrumbs.map((b) => GpsCoord(b.latitude, b.longitude)).toList();
    final insideBc = ring.isNotEmpty ? HlbGeoEngine.filterInsidePolygon(bc, ring) : bc;
    final buildings = state.buildings.map((b) => GpsCoord(b.latitude, b.longitude)).toList();
    if (insideBc.isEmpty && buildings.isEmpty && ring.isEmpty) return [];

    final all = [...insideBc, ...buildings, ...ring.map((p) => GpsCoord(p.lat, p.lng))];
    final bounds = HlbGeoEngine.computeBounds(all);
    final cells = <HeatmapCell>[];

    for (var cx = 0; cx < _gridSize; cx++) {
      for (var cy = 0; cy < _gridSize; cy++) {
        final center = _cellCenter(cx, cy, bounds);
        if (ring.isNotEmpty && !HlbGeoEngine.pointInPolygon(center.lat, center.lng, ring)) continue;
        final visited = insideBc.any((b) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, center.lat, center.lng) < 45);
        final hasBuilding = buildings.any(
          (b) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, center.lat, center.lng) < 50,
        );

        HeatmapCellState s;
        if (!visited) {
          s = HeatmapCellState.unvisited;
        } else if (hasBuilding) {
          s = HeatmapCellState.covered;
        } else {
          final nearbyBuildings = buildings.where(
            (b) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, center.lat, center.lng) < 120,
          ).length;
          s = nearbyBuildings >= 2 ? HeatmapCellState.suspicious : HeatmapCellState.partial;
        }
        cells.add(HeatmapCell(x: cx, y: cy, state: s));
      }
    }
    return cells;
  }

  static List<StreetSegment> computeStreets(HlbLocalState state) {
    final crumbs = state.breadcrumbs;
    if (crumbs.length < 2) return [];

    final segments = <List<LocalBreadcrumb>>[];
    var current = <LocalBreadcrumb>[crumbs.first];

    for (var i = 1; i < crumbs.length; i++) {
      final prev = crumbs[i - 1];
      final cur = crumbs[i];
      final dist = HlbGeoEngine.haversineMeters(prev.latitude, prev.longitude, cur.latitude, cur.longitude);
      if (dist > 80) {
        if (current.length >= 2) segments.add(current);
        current = [cur];
      } else {
        current.add(cur);
      }
    }
    if (current.length >= 2) segments.add(current);

    return segments.asMap().entries.map((entry) {
      final idx = entry.key;
      final seg = entry.value;
      final pts = seg.map((b) => (lat: b.latitude, lng: b.longitude)).toList();
      final mid = pts[pts.length ~/ 2];

      var name = 'Walk Segment ${idx + 1}';
      for (final lm in state.landmarks) {
        if (HlbGeoEngine.haversineMeters(lm.latitude, lm.longitude, mid.lat, mid.lng) < 80) {
          name = 'Near ${lm.name}';
          break;
        }
      }

      final nearBuildings = state.buildings.where((b) {
        return pts.any((p) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, p.lat, p.lng) < 45);
      }).toList();

      final total = nearBuildings.length;
      final confirmed = total;
      final pct = total == 0 ? (seg.length > 5 ? 50 : 0) : 100;

      return StreetSegment(
        id: 'street_$idx',
        name: name,
        buildingsTotal: math.max(total, seg.length ~/ 8),
        buildingsConfirmed: confirmed,
        completionPercent: pct.clamp(0, 100),
        points: pts,
      );
    }).toList();
  }

  static List<DiscoveryReplayEvent> buildReplay(HlbLocalState state) {
    final events = <DiscoveryReplayEvent>[];

    if (state.breadcrumbs.isNotEmpty) {
      events.add(DiscoveryReplayEvent(
        time: state.breadcrumbs.first.recordedAt,
        label: 'Discovery walk started',
        type: 'start',
        latitude: state.breadcrumbs.first.latitude,
        longitude: state.breadcrumbs.first.longitude,
      ));
    }

    for (final node in state.spatialNodes) {
      events.add(DiscoveryReplayEvent(
        time: node.timestamp,
        label: node.label ?? node.type,
        type: node.type,
        latitude: node.latitude,
        longitude: node.longitude,
      ));
    }

    for (final b in state.buildings) {
      if (state.spatialNodes.any((n) => n.linkedEntityId == b.buildingNumber.toString())) continue;
      events.add(DiscoveryReplayEvent(
        time: state.updatedAt,
        label: 'Building CN-${b.buildingNumber.toString().padLeft(3, '0')}',
        type: 'building',
        latitude: b.latitude,
        longitude: b.longitude,
      ));
    }

    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  static int ignoredCount(HlbLocalState state) => state.ignoredSuggestions.length;

  static ({double lat, double lng}) _cellCenter(int cx, int cy, MapBounds bounds) {
    final latSpan = math.max(bounds.maxLat - bounds.minLat, 0.0001);
    final lngSpan = math.max(bounds.maxLng - bounds.minLng, 0.0001);
    final x = (cx + 0.5) / _gridSize;
    final y = (cy + 0.5) / _gridSize;
    return (lat: bounds.maxLat - y * latSpan, lng: bounds.minLng + x * lngSpan);
  }
}
