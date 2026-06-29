import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'hlb_feature_painter.dart';
import 'hlb_official_catalog.dart';

/// Bitmap markers for census buildings and layout-map features on Google Maps.
class HlbCensusSymbols {
  HlbCensusSymbols._();

  static final _buildingIconCache = <String, BitmapDescriptor>{};
  static final _landmarkIconCache = <String, BitmapDescriptor>{};

  static Map<String, String> get buildingTypes => {
        for (final e in HlbOfficialCatalog.buildingEntries) e.id: '${e.glyph} ${e.label}',
      };

  static Future<BitmapDescriptor> buildingMarker(String buildingType) async {
    final cached = _buildingIconCache[buildingType];
    if (cached != null) return cached;

    const size = 56.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2 + 4);
    canvas.drawCircle(center, 22, Paint()..color = Colors.white.withValues(alpha: 0.92));
    HlbFeaturePainter.drawBuilding(canvas, center, buildingType, scale: 1.4);
    final icon = await _bitmapFromCanvas(recorder, size);
    _buildingIconCache[buildingType] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> landmarkMarker(String landmarkType) async {
    final type = HlbOfficialCatalog.normalizeLandmarkType(landmarkType);
    final cached = _landmarkIconCache[type];
    if (cached != null) return cached;

    const size = 52.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, 20, Paint()..color = Colors.white.withValues(alpha: 0.92));
    HlbFeaturePainter.drawLandmark(canvas, center, type, scale: 1.1);
    final icon = await _bitmapFromCanvas(recorder, size);
    _landmarkIconCache[type] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> _bitmapFromCanvas(ui.PictureRecorder recorder, double size) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: size,
      height: size,
    );
  }

  static Future<void> warmBuildingIcons(Iterable<String> types) async {
    for (final type in types) {
      await buildingMarker(type);
    }
  }

  static Future<void> warmLandmarkIcons(Iterable<String> types) async {
    for (final type in types) {
      await landmarkMarker(type);
    }
  }

  @Deprecated('Use HlbFeaturePainter.drawBuilding')
  static void drawBuildingSymbol(Canvas canvas, Offset center, String type, {double scale = 1.0}) {
    HlbFeaturePainter.drawBuilding(canvas, center, type, scale: scale);
  }
}
