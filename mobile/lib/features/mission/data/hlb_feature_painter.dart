import 'package:flutter/material.dart';

import 'hlb_official_catalog.dart';

/// Shared canvas drawing for census buildings and layout-map features (§4.4.3).
class HlbFeaturePainter {
  HlbFeaturePainter._();

  static void drawBuilding(Canvas canvas, Offset center, String type, {double scale = 1.0}) {
    final s = 10.0 * scale;
    final rect = Rect.fromCenter(center: center, width: s * 2, height: s * 2);
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale;

    final isKutcha = type.contains('kutcha');
    final isNonRes = type.contains('non_residential');

    if (isKutcha) {
      final path = Path()
        ..moveTo(center.dx, center.dy - s)
        ..lineTo(center.dx + s, center.dy + s)
        ..lineTo(center.dx - s, center.dy + s)
        ..close();
      if (isNonRes) {
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
        canvas.drawLine(
          Offset(center.dx - s * 0.6, center.dy),
          Offset(center.dx + s * 0.6, center.dy),
          paint..style = PaintingStyle.stroke,
        );
      } else {
        canvas.drawPath(path, paint);
      }
    } else {
      if (isNonRes) {
        canvas.drawRect(rect, paint);
        canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  static void drawLandmark(Canvas canvas, Offset center, String type, {double scale = 1.0}) {
    final id = HlbOfficialCatalog.normalizeLandmarkType(type);
    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * scale;

    switch (id) {
      case 'road':
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy), Offset(center.dx + 10 * scale, center.dy), paint);
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy + 3 * scale), Offset(center.dx + 10 * scale, center.dy + 3 * scale), paint);
      case 'street':
        canvas.drawLine(Offset(center.dx - 8 * scale, center.dy), Offset(center.dx + 8 * scale, center.dy), paint..strokeWidth = 1.0 * scale);
      case 'railway':
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy), Offset(center.dx + 10 * scale, center.dy), paint);
        for (var i = -2; i <= 2; i++) {
          canvas.drawLine(
            Offset(center.dx + i * 4 * scale, center.dy - 4 * scale),
            Offset(center.dx + i * 4 * scale, center.dy + 4 * scale),
            paint..strokeWidth = 1.0 * scale,
          );
        }
      case 'river':
        final path = Path();
        for (var i = -3; i <= 3; i++) {
          final x = center.dx + i * 3 * scale;
          final y = center.dy + (i.isEven ? -2 : 2) * scale;
          if (i == -3) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, paint);
      case 'pond':
        canvas.drawCircle(center, 8 * scale, Paint()..color = const Color(0xFF4FC3F7).withValues(alpha: 0.45));
        canvas.drawCircle(center, 8 * scale, paint);
      case 'hill':
        final hill = Path()
          ..moveTo(center.dx, center.dy - 9 * scale)
          ..lineTo(center.dx + 10 * scale, center.dy + 8 * scale)
          ..lineTo(center.dx - 10 * scale, center.dy + 8 * scale)
          ..close();
        canvas.drawPath(hill, paint);
      case 'hospital':
        canvas.drawLine(Offset(center.dx, center.dy - 7 * scale), Offset(center.dx, center.dy + 7 * scale), paint..strokeWidth = 2 * scale);
        canvas.drawLine(Offset(center.dx - 7 * scale, center.dy), Offset(center.dx + 7 * scale, center.dy), paint..strokeWidth = 2 * scale);
      case 'post_office':
        canvas.drawRect(Rect.fromCenter(center: center, width: 14 * scale, height: 10 * scale), paint);
      case 'place_of_worship':
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - 8 * scale)
            ..lineTo(center.dx + 8 * scale, center.dy + 6 * scale)
            ..lineTo(center.dx - 8 * scale, center.dy + 6 * scale)
            ..close(),
          paint,
        );
      case 'open_space':
        canvas.drawRect(Rect.fromCenter(center: center, width: 14 * scale, height: 14 * scale), paint);
      case 'vacant_plot':
        canvas.drawRect(Rect.fromCenter(center: center, width: 14 * scale, height: 14 * scale), paint);
        canvas.drawLine(
          Offset(center.dx - 5 * scale, center.dy - 5 * scale),
          Offset(center.dx + 5 * scale, center.dy + 5 * scale),
          paint,
        );
      case 'field':
        canvas.drawRect(Rect.fromCenter(center: center, width: 14 * scale, height: 10 * scale), paint);
        for (var i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(center.dx - 6 * scale, center.dy + i * 3 * scale),
            Offset(center.dx + 6 * scale, center.dy + i * 3 * scale),
            paint..strokeWidth = 0.8 * scale,
          );
        }
      case 'forest_settlement':
        canvas.drawCircle(Offset(center.dx - 4 * scale, center.dy + 2 * scale), 4 * scale, paint);
        canvas.drawCircle(Offset(center.dx + 4 * scale, center.dy + 2 * scale), 4 * scale, paint);
        canvas.drawCircle(Offset(center.dx, center.dy - 3 * scale), 4 * scale, paint);
      case 'estate_boundary':
        canvas.drawLine(Offset(center.dx - 7 * scale, center.dy + 7 * scale), Offset(center.dx + 7 * scale, center.dy - 7 * scale), paint);
        canvas.drawLine(Offset(center.dx - 7 * scale, center.dy - 7 * scale), Offset(center.dx - 7 * scale, center.dy + 7 * scale), paint);
        canvas.drawLine(Offset(center.dx - 7 * scale, center.dy + 7 * scale), Offset(center.dx + 7 * scale, center.dy + 7 * scale), paint);
      case 'school':
      case 'shop':
      case 'panchayat':
      case 'hotel':
      case 'office':
      case 'town_hall':
      case 'court':
      case 'shopping_mall':
      case 'other':
        canvas.drawCircle(center, 7 * scale, Paint()..color = Colors.orange.withValues(alpha: 0.3));
        canvas.drawCircle(center, 7 * scale, paint);
        _drawMiniLabel(canvas, center, HlbOfficialCatalog.landmarkGlyph(id) ?? '•', scale);
    }
  }

  static void _drawMiniLabel(Canvas canvas, Offset center, String text, double scale) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.black87, fontSize: 7 * scale, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static void drawLegend(
    Canvas canvas,
    Rect bounds, {
    Iterable<String>? landmarkTypesOnMap,
  }) {
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFDE7));
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black45
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    var y = bounds.top + 6;
    const x = 4.0;
    y = _legendHeading(canvas, 'Legend', x, y, bounds.width - 8);
    y = _legendHeading(canvas, 'Buildings', x, y, bounds.width - 8, size: 8);

    for (final entry in HlbOfficialCatalog.buildingEntries) {
      drawBuilding(canvas, Offset(bounds.left + 14, y + 8), entry.id, scale: 0.65);
      y = _legendRow(canvas, entry.label, x + 24, y, bounds.width - 28, size: 7);
    }

    y += 4;
    y = _legendHeading(canvas, 'Features', x, y, bounds.width - 8, size: 8);

    final onMap = landmarkTypesOnMap?.map(HlbOfficialCatalog.normalizeLandmarkType).toSet() ?? {};
    final featureEntries = onMap.isEmpty
        ? HlbOfficialCatalog.landmarkEntries.where((e) => e.id != 'other').take(14)
        : HlbOfficialCatalog.landmarkEntries.where((e) => onMap.contains(e.id));

    for (final entry in featureEntries) {
      drawLandmark(canvas, Offset(bounds.left + 14, y + 8), entry.id, scale: 0.6);
      y = _legendRow(canvas, entry.label, x + 24, y, bounds.width - 28, size: 6.5);
      if (y > bounds.bottom - 10) break;
    }
  }

  static double _legendHeading(Canvas canvas, String text, double x, double y, double maxW, {double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.black87)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(x, y));
    return y + tp.height + 2;
  }

  static double _legendRow(Canvas canvas, String text, double x, double y, double maxW, {double size = 7}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: Colors.black87)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(x, y));
    return y + tp.height + 3;
  }
}
