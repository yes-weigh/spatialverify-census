import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mission_models.dart';
import 'hlb_official_catalog.dart';

/// Shared canvas drawing for census buildings and layout-map features (§4.4.3 / Census 2027 sample).
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
      case 'pucca_road':
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy - 2 * scale), Offset(center.dx + 10 * scale, center.dy - 2 * scale), paint);
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy + 2 * scale), Offset(center.dx + 10 * scale, center.dy + 2 * scale), paint);
      case 'kutcha_road':
        _drawDashedLine(canvas, Offset(center.dx - 10 * scale, center.dy - 2 * scale), Offset(center.dx + 10 * scale, center.dy - 2 * scale), paint);
        _drawDashedLine(canvas, Offset(center.dx - 10 * scale, center.dy + 2 * scale), Offset(center.dx + 10 * scale, center.dy + 2 * scale), paint);
      case 'street':
        canvas.drawLine(Offset(center.dx - 8 * scale, center.dy), Offset(center.dx + 8 * scale, center.dy), paint..strokeWidth = 1.0 * scale);
      case 'canal':
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy - 3 * scale), Offset(center.dx + 10 * scale, center.dy - 3 * scale), paint..color = const Color(0xFF1565C0));
        canvas.drawLine(Offset(center.dx - 10 * scale, center.dy + 3 * scale), Offset(center.dx + 10 * scale, center.dy + 3 * scale), paint..color = const Color(0xFF1565C0));
        for (var i = -2; i <= 2; i++) {
          canvas.drawLine(
            Offset(center.dx + i * 4 * scale, center.dy - 3 * scale),
            Offset(center.dx + i * 4 * scale, center.dy + 3 * scale),
            paint..strokeWidth = 0.6 * scale,
          );
        }
      case 'path':
        for (var i = -2; i <= 2; i++) {
          canvas.drawCircle(Offset(center.dx + i * 4 * scale, center.dy), 1.2 * scale, Paint()..color = Colors.black54);
        }
      case 'well':
        canvas.drawCircle(center, 6 * scale, paint);
        canvas.drawLine(Offset(center.dx, center.dy - 6 * scale), Offset(center.dx, center.dy - 10 * scale), paint);
      case 'tap':
        canvas.drawCircle(center, 3 * scale, Paint()..color = Colors.black87);
        canvas.drawLine(Offset(center.dx, center.dy), Offset(center.dx, center.dy + 8 * scale), paint);
      case 'handpump':
        canvas.drawRect(Rect.fromCenter(center: center + Offset(0, 2 * scale), width: 8 * scale, height: 6 * scale), paint);
        canvas.drawLine(Offset(center.dx, center.dy - 4 * scale), Offset(center.dx, center.dy - 10 * scale), paint..strokeWidth = 2 * scale);
      case 'temple':
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - 8 * scale)
            ..lineTo(center.dx + 7 * scale, center.dy + 5 * scale)
            ..lineTo(center.dx - 7 * scale, center.dy + 5 * scale)
            ..close(),
          paint,
        );
        canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, center.dy + 6 * scale), width: 10 * scale, height: 4 * scale), paint);
      case 'mosque':
        canvas.drawRect(Rect.fromCenter(center: center, width: 12 * scale, height: 10 * scale), paint);
        canvas.drawCircle(Offset(center.dx, center.dy - 8 * scale), 3 * scale, paint);
      case 'church':
        canvas.drawRect(Rect.fromCenter(center: center + Offset(0, 2 * scale), width: 10 * scale, height: 10 * scale), paint);
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - 10 * scale)
            ..lineTo(center.dx + 6 * scale, center.dy - 2 * scale)
            ..lineTo(center.dx - 6 * scale, center.dy - 2 * scale)
            ..close(),
          paint,
        );
      case 'gurudwara':
        canvas.drawRect(Rect.fromCenter(center: center, width: 12 * scale, height: 8 * scale), paint);
        canvas.drawLine(Offset(center.dx - 6 * scale, center.dy - 4 * scale), Offset(center.dx + 6 * scale, center.dy - 4 * scale), paint..strokeWidth = 2 * scale);
        _drawMiniLabel(canvas, center + Offset(0, 2 * scale), 'Kh', scale);
      case 'market':
        canvas.drawRect(Rect.fromCenter(center: center, width: 14 * scale, height: 10 * scale), paint);
        _drawMiniLabel(canvas, center, 'Mk', scale);
      case 'building_cluster':
        canvas.drawRect(Rect.fromCenter(center: center, width: 12 * scale, height: 12 * scale), paint);
        canvas.drawRect(Rect.fromCenter(center: center + Offset(4 * scale, 4 * scale), width: 10 * scale, height: 10 * scale), paint..strokeWidth = 1.0 * scale);
      case 'isolated_building':
        canvas.drawRect(Rect.fromCenter(center: center, width: 10 * scale, height: 10 * scale), paint);
        canvas.drawCircle(center + Offset(12 * scale, -10 * scale), 2 * scale, Paint()..color = Colors.black54);
      case 'adjacent_hlb':
        _drawMiniLabel(canvas, center, 'HLB', scale * 0.9);
        canvas.drawRect(Rect.fromCenter(center: center, width: 22 * scale, height: 12 * scale), paint..strokeWidth = 1 * scale);
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

  static Color lineFeatureColor(String type) {
    switch (HlbOfficialCatalog.normalizeLineType(type)) {
      case 'kutcha_road':
      case 'street':
        return const Color(0xFF616161);
      case 'canal':
      case 'river':
        return const Color(0xFF1565C0);
      case 'railway':
        return const Color(0xFF212121);
      case 'path':
        return const Color(0xFF795548);
      default:
        return const Color(0xFF37474F);
    }
  }

  static void drawLineFeature(Canvas canvas, List<Offset> points, String type, {double scale = 1.0}) {
    if (points.length < 2) return;
    final id = HlbOfficialCatalog.normalizeLineType(type);
    final color = lineFeatureColor(id);

    if (id == 'pucca_road' || id == 'kutcha_road') {
      _drawDoubleLine(canvas, points, color, dashed: id == 'kutcha_road', scale: scale);
      return;
    }

    if (id == 'river') {
      _drawWavyPath(canvas, points, color, scale: scale);
      return;
    }

    if (id == 'canal') {
      _drawCanalPath(canvas, points, color, scale: scale);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = id == 'path' ? 1.6 * scale : 2.4 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (id == 'street' || id == 'path') {
      _drawDashedPath(canvas, path, paint, dash: id == 'path' ? 4 : 6, gap: id == 'path' ? 4 : 5);
    } else if (id == 'railway') {
      canvas.drawPath(path, paint);
      _drawRailwayTicks(canvas, points, scale);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  static void drawOfficialBoundary(Canvas canvas, Path path, {bool closed = true}) {
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.06)..style = PaintingStyle.fill);
    _drawDashDotPath(canvas, path, Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);
  }

  static void drawEndpointLabel(Canvas canvas, Offset point, String title, String subtitle) {
    canvas.drawCircle(point, 5, Paint()..color = const Color(0xFFD84315));
    drawAngledText(canvas, point + const Offset(8, -14), title, rotationDegrees: 0, size: 8, weight: FontWeight.w800);
    if (subtitle.isNotEmpty) {
      drawAngledText(canvas, point + const Offset(8, -4), subtitle, rotationDegrees: 0, size: 7, weight: FontWeight.w600);
    }
  }

  static void drawAngledText(
    Canvas canvas,
    Offset anchor,
    String text, {
    double rotationDegrees = 0,
    double size = 8,
    FontWeight weight = FontWeight.w500,
    Color color = Colors.black87,
  }) {
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(rotationDegrees * math.pi / 180);
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  static void drawTitleBlock(Canvas canvas, Rect bounds, DraftHlbTitleBlock block) {
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    var y = bounds.top + 5;
    canvas.drawRect(
      Rect.fromLTWH(bounds.left, y, bounds.width, 14),
      Paint()..color = const Color(0xFFECEFF1),
    );
    drawAngledText(
      canvas,
      Offset(bounds.left + bounds.width / 2, y + 2),
      'LAYOUT MAP — HOUSE LISTING BLOCK',
      size: 9,
      weight: FontWeight.w800,
    );

    y += 16;
    for (final line in block.lines) {
      final tp = TextPainter(
        text: TextSpan(
          text: line,
          style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: bounds.width - 12);
      tp.paint(canvas, Offset(bounds.left + 6, y));
      y += tp.height + 1.5;
    }
  }

  static void drawFooterBlock(Canvas canvas, Rect bounds, DraftHlbFooterBlock block) {
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final colW = bounds.width / 2;
    _drawFooterColumn(canvas, Rect.fromLTWH(bounds.left, bounds.top, colW, bounds.height), 'Enumerator', block.enumeratorName, block.enumeratorDate);
    _drawFooterColumn(
      canvas,
      Rect.fromLTWH(bounds.left + colW, bounds.top, colW, bounds.height),
      'Supervisor',
      block.supervisorName,
      block.supervisorDate,
    );
  }

  static void _drawFooterColumn(Canvas canvas, Rect r, String role, String? name, String? date) {
    drawAngledText(canvas, Offset(r.left + 8, r.top + 6), role, size: 8, weight: FontWeight.w800);
    drawAngledText(canvas, Offset(r.left + 8, r.top + 20), 'Name: ${name ?? '________________'}', size: 7);
    drawAngledText(canvas, Offset(r.left + 8, r.top + 32), 'Date: ${date ?? '____/____/______'}', size: 7);
    drawAngledText(canvas, Offset(r.left + 8, r.top + 48), 'Signature: ________________', size: 7);
  }

  static void drawSerpentineArrow(Canvas canvas, Offset from, Offset to, {double scale = 1.0}) {
    final paint = Paint()
      ..color = const Color(0xFFD84315)
      ..strokeWidth = 1.6 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 4) return;

    final ux = dx / len;
    final uy = dy / len;
    final shortened = Offset(to.dx - ux * 10 * scale, to.dy - uy * 10 * scale);
    canvas.drawLine(from, shortened, paint);

    final angle = math.atan2(dy, dx);
    const wing = 0.45;
    final wingLen = 7 * scale;
    final p1 = Offset(
      shortened.dx - wingLen * math.cos(angle - wing),
      shortened.dy - wingLen * math.sin(angle - wing),
    );
    final p2 = Offset(
      shortened.dx - wingLen * math.cos(angle + wing),
      shortened.dy - wingLen * math.sin(angle + wing),
    );
    canvas.drawLine(shortened, p1, paint);
    canvas.drawLine(shortened, p2, paint);
  }

  static void drawLegend(Canvas canvas, Rect bounds, {Iterable<String>? landmarkTypesOnMap}) {
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFDE7));
    canvas.drawRect(
      bounds,
      Paint()
        ..color = Colors.black45
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    var y = bounds.top + 4;
    const x = 3.0;
    y = _legendHeading(canvas, 'Legend', x, y, bounds.width - 6);
    y = _legendHeading(canvas, 'Buildings', x, y, bounds.width - 6, size: 7);

    for (final entry in HlbOfficialCatalog.buildingEntries) {
      drawBuilding(canvas, Offset(bounds.left + 12, y + 7), entry.id, scale: 0.55);
      y = _legendRow(canvas, entry.label, x + 20, y, bounds.width - 24, size: 6);
    }

    for (final category in HlbCatalogCategory.values) {
      if (category == HlbCatalogCategory.buildings) continue;
      y += 2;
      y = _legendHeading(canvas, HlbOfficialCatalog.categoryLabels[category]!, x, y, bounds.width - 6, size: 7);
      final onMap = landmarkTypesOnMap?.map(HlbOfficialCatalog.normalizeLandmarkType).toSet() ?? {};
      final entries = onMap.isEmpty
          ? HlbOfficialCatalog.landmarksInCategory(category).where((e) => !HlbOfficialCatalog.isLineFeatureType(e.id))
          : HlbOfficialCatalog.landmarksInCategory(category).where((e) => onMap.contains(e.id));
      for (final entry in entries) {
        if (HlbOfficialCatalog.isLineFeatureType(entry.id)) {
          drawLineFeature(
            canvas,
            [Offset(bounds.left + 4, y + 8), Offset(bounds.left + 20, y + 8)],
            entry.id,
            scale: 0.5,
          );
        } else {
          drawLandmark(canvas, Offset(bounds.left + 12, y + 8), entry.id, scale: 0.5);
        }
        y = _legendRow(canvas, entry.label, x + 20, y, bounds.width - 24, size: 5.5);
        if (y > bounds.bottom - 8) return;
      }
    }
  }

  static void _drawDoubleLine(Canvas canvas, List<Offset> points, Color color, {required bool dashed, double scale = 1.0}) {
    for (final offset in [-2.5 * scale, 2.5 * scale]) {
      final offsetPts = _parallelOffset(points, offset);
      if (offsetPts.length < 2) continue;
      final path = Path()..moveTo(offsetPts.first.dx, offsetPts.first.dy);
      for (var i = 1; i < offsetPts.length; i++) {
        path.lineTo(offsetPts[i].dx, offsetPts[i].dy);
      }
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.8 * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (dashed) {
        _drawDashedPath(canvas, path, paint, dash: 5, gap: 4);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  static List<Offset> _parallelOffset(List<Offset> points, double offset) {
    if (points.length < 2) return points;
    final out = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final a = i == 0 ? points[i] : points[i - 1];
      final b = i == points.length - 1 ? points[i] : points[i + 1];
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx) + math.pi / 2;
      out.add(Offset(points[i].dx + math.cos(angle) * offset, points[i].dy + math.sin(angle) * offset));
    }
    return out;
  }

  static void _drawWavyPath(Canvas canvas, List<Offset> points, Color color, {double scale = 1.0}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final steps = 8;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final x = a.dx + (b.dx - a.dx) * t;
        final y = a.dy + (b.dy - a.dy) * t + math.sin(t * math.pi * 3) * 2 * scale;
        if (i == 0 && s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  static void _drawCanalPath(Canvas canvas, List<Offset> points, Color color, {double scale = 1.0}) {
    _drawDoubleLine(canvas, points, color, dashed: false, scale: scale);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final steps = 4;
      for (var s = 1; s < steps; s++) {
        final t = s / steps;
        final p = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
        canvas.drawLine(Offset(p.dx, p.dy - 3 * scale), Offset(p.dx, p.dy + 3 * scale), Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 0.8 * scale);
      }
    }
  }

  static void _drawDashDotPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var long = true;
      while (distance < metric.length) {
        final len = long ? 10.0 : 3.0;
        final next = distance + len;
        final extract = metric.extractPath(distance, next.clamp(0, metric.length));
        canvas.drawPath(extract, paint);
        distance = next + (long ? 4.0 : 8.0);
        long = !long;
      }
    }
  }

  static void _drawDashedPath(Canvas canvas, Path path, Paint paint, {required double dash, required double gap}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        final extract = metric.extractPath(distance, next.clamp(0, metric.length));
        canvas.drawPath(extract, paint);
        distance = next + gap;
      }
    }
  }

  static void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 4, double gap = 3}) {
    final path = Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy);
    _drawDashedPath(canvas, path, paint, dash: dash, gap: gap);
  }

  static void _drawRailwayTicks(Canvas canvas, List<Offset> points, double scale) {
    final tickPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.0 * scale;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final perp = angle + math.pi / 2;
      final dx = math.cos(perp) * 4 * scale;
      final dy = math.sin(perp) * 4 * scale;
      canvas.drawLine(Offset(mid.dx - dx, mid.dy - dy), Offset(mid.dx + dx, mid.dy + dy), tickPaint);
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

  static double _legendHeading(Canvas canvas, String text, double x, double y, double maxW, {double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.black87)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(x, y));
    return y + tp.height + 1;
  }

  static double _legendRow(Canvas canvas, String text, double x, double y, double maxW, {double size = 7}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: Colors.black87)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(x, y));
    return y + tp.height + 2;
  }
}
