import 'package:flutter/material.dart';

import '../data/discovery_analytics.dart';
import '../models/mission_models.dart';

/// Discovery heatmap + road coverage layer on mini-map.
class DiscoveryHeatmapPainter extends CustomPainter {
  DiscoveryHeatmapPainter({
    required this.mapData,
    required this.heatmapCells,
    this.roadSegments = const [],
    this.showRoadLayer = true,
  });

  final DraftHlbMap mapData;
  final List<HeatmapCell> heatmapCells;
  final List<StreetSegment> roadSegments;
  final bool showRoadLayer;

  static const _gridSize = 8;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;

    for (final cell in heatmapCells) {
      final x = pad + (cell.x / _gridSize) * drawW;
      final y = pad + (cell.y / _gridSize) * drawH;
      final w = drawW / _gridSize;
      final h = drawH / _gridSize;
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()..color = _cellColor(cell.state),
      );
    }

    if (showRoadLayer && mapData.walkPath.length >= 2) {
      final path = Path();
      for (var i = 0; i < mapData.walkPath.length; i++) {
        final p = mapData.walkPath[i];
        final sx = pad + p.x * drawW;
        final sy = pad + p.y * drawH;
        if (i == 0) {
          path.moveTo(sx, sy);
        } else {
          path.lineTo(sx, sy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFD740).withValues(alpha: 0.85)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }

    if (mapData.boundary.length >= 2) {
      final path = Path();
      for (var i = 0; i < mapData.boundary.length; i++) {
        final p = mapData.boundary[i];
        final sx = pad + p.x * drawW;
        final sy = pad + p.y * drawH;
        if (i == 0) {
          path.moveTo(sx, sy);
        } else {
          path.lineTo(sx, sy);
        }
      }
      canvas.drawPath(path, Paint()..color = Colors.white24..strokeWidth = 1..style = PaintingStyle.stroke);
    }

    for (final b in mapData.buildings) {
      final p = Offset(pad + b.mapX * drawW, pad + b.mapY * drawH);
      canvas.drawRect(Rect.fromCenter(center: p, width: 4, height: 4), Paint()..color = const Color(0xFF00E676));
    }
  }

  Color _cellColor(HeatmapCellState s) {
    switch (s) {
      case HeatmapCellState.covered:
        return const Color(0xFF00E676).withValues(alpha: 0.45);
      case HeatmapCellState.partial:
        return const Color(0xFFFF9800).withValues(alpha: 0.45);
      case HeatmapCellState.suspicious:
        return const Color(0xFFE53935).withValues(alpha: 0.5);
      case HeatmapCellState.unvisited:
        return const Color(0xFF616161).withValues(alpha: 0.35);
    }
  }

  @override
  bool shouldRepaint(covariant DiscoveryHeatmapPainter old) =>
      old.heatmapCells != heatmapCells || old.mapData != mapData;
}
