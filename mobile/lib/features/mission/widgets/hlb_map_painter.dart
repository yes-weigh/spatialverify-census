import 'package:flutter/material.dart';
import '../models/mission_models.dart';
import '../data/hlb_feature_painter.dart';

/// Census HLB layout map renderer with official legend (§4.4.3).
class HlbMapPainter extends CustomPainter {
  HlbMapPainter({
    required this.mapData,
    this.gaps = const [],
    this.selectedGapId,
    this.highlightGaps = false,
    this.showLegend = true,
  });

  final DraftHlbMap mapData;
  final List<CoverageGap> gaps;
  final String? selectedGapId;
  final bool highlightGaps;
  final bool showLegend;

  static const _pad = 24.0;
  static const _legendW = 92.0;

  @override
  void paint(Canvas canvas, Size size) {
    final legendW = showLegend ? _legendW : 0.0;
    final mapLeft = _pad + legendW;
    final drawW = size.width - mapLeft - _pad;
    final drawH = size.height - _pad * 2;

    Offset toScreen(double x, double y) => Offset(mapLeft + x * drawW, _pad + y * drawH);

    if (showLegend) {
      HlbFeaturePainter.drawLegend(
        canvas,
        Rect.fromLTWH(_pad, _pad, _legendW, drawH),
        landmarkTypesOnMap: mapData.landmarks.map((lm) => lm.type),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(mapLeft, _pad, drawW, drawH),
      Paint()..color = const Color(0xFFFFFDE7),
    );
    canvas.drawRect(
      Rect.fromLTWH(mapLeft, _pad, drawW, drawH),
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final northTip = Offset(size.width - 36, _pad + 12);
    canvas.drawLine(northTip + const Offset(0, 16), northTip, Paint()..color = Colors.black..strokeWidth = 2);
    _drawText(canvas, 'N', northTip + const Offset(-4, -14), 11, FontWeight.bold);

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
          ..color = Colors.blue.withValues(alpha: 0.35)
          ..strokeWidth = 2
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
      final boundaryColor = mapData.isOfficialBoundary ? const Color(0xFF00E676) : Colors.red;
      canvas.drawPath(path, Paint()..color = boundaryColor.withValues(alpha: 0.15)..style = PaintingStyle.fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = boundaryColor
          ..strokeWidth = mapData.isOfficialBoundary ? 3 : 2
          ..style = PaintingStyle.stroke,
      );
    }

    for (final lm in mapData.landmarks) {
      final p = toScreen(lm.mapX, lm.mapY);
      HlbFeaturePainter.drawLandmark(canvas, p, lm.type, scale: 0.95);
      final shortName = lm.name.length > 10 ? lm.name.substring(0, 10) : lm.name;
      _drawText(canvas, shortName, p + const Offset(-14, -16), 7.5, FontWeight.w500);
    }

    for (final b in mapData.buildings) {
      final p = toScreen(b.mapX, b.mapY);
      HlbFeaturePainter.drawBuilding(canvas, p, b.buildingType);
      _drawText(canvas, b.label, p + const Offset(-16, -22), 9, FontWeight.w600);
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

    _drawText(canvas, 'HLB ${mapData.ebCode} — Layout map', Offset(mapLeft, 4), 12, FontWeight.bold);
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

  void _drawText(Canvas canvas, String text, Offset offset, double size, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: Colors.black87, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant HlbMapPainter old) =>
      old.mapData != mapData || old.gaps != gaps || old.selectedGapId != selectedGapId || old.showLegend != showLegend;
}
