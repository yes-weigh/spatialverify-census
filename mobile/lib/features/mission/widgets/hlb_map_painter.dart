import 'package:flutter/material.dart';
import '../models/mission_models.dart';
import '../data/hlb_feature_painter.dart';

/// Census HLB layout map renderer — Census 2027 sample form layout.
class HlbMapPainter extends CustomPainter {
  HlbMapPainter({
    required this.mapData,
    this.gaps = const [],
    this.selectedGapId,
    this.highlightGaps = false,
    this.showLegend = true,
    this.showFooter = true,
  });

  final DraftHlbMap mapData;
  final List<CoverageGap> gaps;
  final String? selectedGapId;
  final bool highlightGaps;
  final bool showLegend;
  final bool showFooter;

  static const _pad = 20.0;
  static const _legendW = 108.0;
  static const _titleH = 88.0;
  static const _footerH = 58.0;

  @override
  void paint(Canvas canvas, Size size) {
    final legendW = showLegend ? _legendW : 0.0;
    final titleH = mapData.titleBlock != null ? _titleH : 0.0;
    final footerH = showFooter ? _footerH : 0.0;
    final mapLeft = _pad + legendW;
    final mapTop = _pad + titleH;
    final drawW = size.width - mapLeft - _pad;
    final drawH = size.height - mapTop - _pad - footerH;

    Offset toScreen(double x, double y) => Offset(mapLeft + x * drawW, mapTop + y * drawH);

    if (showLegend) {
      HlbFeaturePainter.drawLegend(
        canvas,
        Rect.fromLTWH(_pad, mapTop, _legendW, drawH),
        landmarkTypesOnMap: {
          ...mapData.landmarks.map((lm) => lm.type),
          ...mapData.lineFeatures.map((lf) => lf.segmentType),
        },
      );
    }

    if (mapData.titleBlock != null) {
      HlbFeaturePainter.drawTitleBlock(
        canvas,
        Rect.fromLTWH(mapLeft, _pad, drawW, titleH - 4),
        mapData.titleBlock!,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(mapLeft, mapTop, drawW, drawH),
      Paint()..color = const Color(0xFFFFFDE7),
    );
    canvas.drawRect(
      Rect.fromLTWH(mapLeft, mapTop, drawW, drawH),
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final northTip = Offset(size.width - 32, mapTop + 10);
    canvas.drawLine(northTip + const Offset(0, 14), northTip, Paint()..color = Colors.black..strokeWidth = 2);
    HlbFeaturePainter.drawAngledText(canvas, northTip + const Offset(-4, -12), 'N', size: 10, weight: FontWeight.bold);

    if (mapData.walkPath.length >= 2) {
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
          ..color = Colors.blue.withValues(alpha: 0.25)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    if (mapData.boundary.length >= 2) {
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

    for (final lm in mapData.landmarks) {
      final p = toScreen(lm.mapX, lm.mapY);
      HlbFeaturePainter.drawLandmark(canvas, p, lm.type, scale: 0.95);
      if (lm.name.isNotEmpty) {
        HlbFeaturePainter.drawAngledText(canvas, p + const Offset(-12, -14), lm.name, size: 7, weight: FontWeight.w500);
      }
    }

    for (final b in mapData.buildings) {
      final p = toScreen(b.mapX, b.mapY);
      HlbFeaturePainter.drawBuilding(canvas, p, b.buildingType);
      HlbFeaturePainter.drawAngledText(canvas, p + const Offset(-14, -20), b.label, size: 8.5, weight: FontWeight.w700);
    }

    for (final arrow in mapData.serpentineArrows) {
      HlbFeaturePainter.drawSerpentineArrow(
        canvas,
        toScreen(arrow.fromX, arrow.fromY),
        toScreen(arrow.toX, arrow.toY),
      );
    }

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

    if (showFooter) {
      HlbFeaturePainter.drawFooterBlock(
        canvas,
        Rect.fromLTWH(mapLeft, mapTop + drawH + 4, drawW, footerH - 4),
        mapData.footerBlock,
      );
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
  bool shouldRepaint(covariant HlbMapPainter old) =>
      old.mapData != mapData ||
      old.gaps != gaps ||
      old.selectedGapId != selectedGapId ||
      old.showLegend != showLegend ||
      old.showFooter != showFooter;
}
