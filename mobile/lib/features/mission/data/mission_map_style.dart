import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
/// Shared HLB boundary styling for Google Maps and flutter_map canvases.
class MissionMapStyle {
  MissionMapStyle._();

  static const boundaryColor = Color(0xFFFF1744);
  static const boundaryWidth = 2.0;

  static List<PatternItem> get googleBoundaryPattern => [
        PatternItem.dot,
        PatternItem.gap(5),
      ];

  static List<PatternItem> googleBoundaryPatterns({required bool complete}) {
    if (complete) return googleBoundaryPattern;
    return [
      PatternItem.dash(8),
      PatternItem.gap(6),
      PatternItem.dot,
      PatternItem.gap(4),
    ];
  }

  static fm.StrokePattern flutterBoundaryPattern({required bool complete}) {
    if (complete) return const fm.StrokePattern.dotted();
    return fm.StrokePattern.dashed(segments: const [8, 6]);
  }

  /// Plain backdrop when Google tiles are hidden (PDF / HLB layers still visible).
  static const basemapOffBackground = Color(0xFF1A1A22);

  /// Hides satellite/road tiles while keeping overlays (PDF, markers, polylines).
  static const hiddenBasemapJson = '''
[
  {"featureType": "all", "elementType": "geometry", "stylers": [{"visibility": "off"}]},
  {"featureType": "all", "elementType": "labels", "stylers": [{"visibility": "off"}]}
]
''';

  static BitmapDescriptor? _userLocationGoogleIcon;

  /// Google Maps web ignores [GoogleMap.myLocationEnabled]; use this marker instead.
  static Future<BitmapDescriptor> userLocationGoogleIcon() async {
    if (_userLocationGoogleIcon != null) return _userLocationGoogleIcon!;

    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, 16, Paint()..color = const Color(0x334285F4));
    canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF4285F4));
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    _userLocationGoogleIcon = BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: size,
      height: size,
    );
    return _userLocationGoogleIcon!;
  }
}
