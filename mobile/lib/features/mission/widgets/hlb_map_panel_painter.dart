import 'package:flutter/material.dart';

import '../models/mission_models.dart';
import '../data/hlb_feature_painter.dart';

/// Field drawings only — overlays on the imported PDF map panel (transparent background).
class HlbMapPanelPainter extends CustomPainter {
  HlbMapPanelPainter({
    required this.mapData,
    this.gaps = const [],
    this.selectedGapId,
    this.highlightGaps = false,
    this.showBoundary = true,
    this.showBuildings = true,
    this.showLandmarks = true,
    this.showLineFeatures = true,
    this.showWalkPath = true,
    this.showEndpoints = true,
  });

  final DraftHlbMap mapData;
  final List<CoverageGap> gaps;
  final String? selectedGapId;
  final bool highlightGaps;
  final bool showBoundary;
  final bool showBuildings;
  final bool showLandmarks;
  final bool showLineFeatures;
  final bool showWalkPath;
  final bool showEndpoints;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toScreen(double x, double y) => Offset(x * size.width, y * size.height);

    if (showWalkPath && mapData.walkPath.length >= 2) {
      final path = Path();
      for (var i = 0; i < mapData.walkPath.length; i++) {
        final p = toScreen(mapData.walkPath[i].x, mapData.walkPath[i].y);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.35)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    if (showBoundary && mapData.boundary.length >= 2) {
      final path = Path();
      for (var i = 0; i < mapData.boundary.length; i++) {
        final p = toScreen(mapData.boundary[i].x, mapData.boundary[i].y);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (mapData.boundaryClosed && mapData.boundary.length >= 3) path.close();
      if (mapData.isOfficialBoundary) {
        HlbFeaturePainter.drawOfficialBoundary(canvas, path, closed: mapData.boundaryClosed);
      } else {
        canvas.drawPath(path, Paint()..color = Colors.red.withValues(alpha: 0.12)..style = PaintingStyle.fill);
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    if (showLineFeatures) {
      for (final lf in mapData.lineFeatures) {
        if (lf.points.length < 2) continue;
        final pts = lf.points.map((p) => toScreen(p.x, p.y)).toList();
        HlbFeaturePainter.drawLineFeature(canvas, pts, lf.segmentType);
        if (lf.name != null && lf.name!.isNotEmpty && pts.length >= 2) {
          final mid = pts[pts.length ~/ 2];
          HlbFeaturePainter.drawAngledText(
            canvas,
            mid,
            lf.name!,
            rotationDegrees: lf.labelRotation,
            size: 7.5,
            weight: FontWeight.w600,
          );
        }
      }

      for (final ann in mapData.annotations) {
        HlbFeaturePainter.drawAngledText(
          canvas,
          toScreen(ann.mapX, ann.mapY),
          ann.text,
          rotationDegrees: ann.rotationDegrees,
          size: ann.annotationType == 'road_name' ? 7.5 : 7,
          weight: FontWeight.w600,
          color: ann.annotationType == 'adjacent_hlb' ? const Color(0xFF1565C0) : Colors.black87,
        );
      }

      for (final arrow in mapData.serpentineArrows) {
        HlbFeaturePainter.drawSerpentineArrow(
          canvas,
          toScreen(arrow.fromX, arrow.fromY),
          toScreen(arrow.toX, arrow.toY),
        );
      }
    }

    if (showLandmarks) {
      for (final lm in mapData.landmarks) {
        final p = toScreen(lm.mapX, lm.mapY);
        HlbFeaturePainter.drawLandmark(canvas, p, lm.type, scale: 0.95);
        if (lm.name.isNotEmpty) {
          HlbFeaturePainter.drawAngledText(canvas, p + const Offset(-12, -14), lm.name, size: 7, weight: FontWeight.w500);
        }
      }
    }

    if (showBuildings) {
      for (final b in mapData.buildings) {
        final p = toScreen(b.mapX, b.mapY);
        HlbFeaturePainter.drawBuilding(canvas, p, b.buildingType);
        HlbFeaturePainter.drawAngledText(canvas, p + const Offset(-14, -20), b.label, size: 8.5, weight: FontWeight.w700);
      }
    }

    if (showEndpoints) {
      if (mapData.startPoint != null) {
        final p = toScreen(mapData.startPoint!.mapX, mapData.startPoint!.mapY);
        HlbFeaturePainter.drawEndpointLabel(
          canvas,
          p,
          mapData.startPoint!.label,
          mapData.startPoint!.buildingNumber?.toString() ?? '',
        );
      }
      if (mapData.endPoint != null) {
        final p = toScreen(mapData.endPoint!.mapX, mapData.endPoint!.mapY);
        HlbFeaturePainter.drawEndpointLabel(
          canvas,
          p,
          mapData.endPoint!.label,
          mapData.endPoint!.buildingNumber?.toString() ?? '',
        );
      }
    }

    if (highlightGaps) {
      for (final g in gaps) {
        if (g.isResolved || g.mapX == null || g.mapY == null) continue;
        final p = toScreen(g.mapX!, g.mapY!);
        final isSelected = g.id == selectedGapId;
        final color = _severityColor(g.severity);
        canvas.drawCircle(p, isSelected ? 14 : 9, Paint()..color = color.withValues(alpha: isSelected ? 0.35 : 0.2));
        canvas.drawCircle(
          p,
          isSelected ? 14 : 9,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 3 : 1.5,
        );
      }
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'high':
        return const Color(0xFFD32F2F);
      case 'low':
        return const Color(0xFF757575);
      default:
        return const Color(0xFFF57C00);
    }
  }

  @override
  bool shouldRepaint(covariant HlbMapPanelPainter old) =>
      old.mapData != mapData ||
      old.gaps != gaps ||
      old.selectedGapId != selectedGapId ||
      old.highlightGaps != highlightGaps ||
      old.showBoundary != showBoundary ||
      old.showBuildings != showBuildings ||
      old.showLandmarks != showLandmarks ||
      old.showLineFeatures != showLineFeatures ||
      old.showWalkPath != showWalkPath ||
      old.showEndpoints != showEndpoints;
}
