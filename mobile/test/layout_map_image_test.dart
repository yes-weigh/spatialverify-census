import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spatialverify/core/spatial_cv/spatial_cv_image.dart';

void main() {
  test('trimWhiteMargins removes outer page margins', () {
    final src = img.Image(width: 200, height: 120);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    for (var y = 30; y < 90; y++) {
      for (var x = 50; x < 170; x++) {
        src.setPixel(x, y, img.ColorRgb8(80, 120, 60));
      }
    }

    final trimmed = trimWhiteMargins(src);
    expect(trimmed.width, lessThan(src.width));
    expect(trimmed.height, lessThan(src.height));
    expect(trimmed.width, 122);
    expect(trimmed.height, 62);
  });

  test('import render keeps full page (legend + margins visible on map)', () {
    final src = img.Image(width: 400, height: 200);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    // Left legend strip
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 100; x++) {
        src.setPixel(x, y, img.ColorRgb8(200, 200, 200));
      }
    }
    // Map panel
    for (var y = 20; y < 180; y++) {
      for (var x = 120; x < 390; x++) {
        src.setPixel(x, y, img.ColorRgb8(70, 110, 55));
      }
    }
    final full = Uint8List.fromList(img.encodePng(src));
    final cropped = prepareLayoutMapImageBytes(full);
    final croppedImg = img.decodeImage(cropped)!;
    expect(croppedImg.width, lessThan(src.width));
    expect(full.length, greaterThan(cropped.length));
  });

  test('detectBoundary scans full width on panel-only images', () {
    final src = img.Image(width: 300, height: 200);
    img.fill(src, color: img.ColorRgb8(60, 90, 50));
    for (var t = 0; t < 300; t++) {
      src.setPixel(t, 40, img.ColorRgb8(240, 240, 240));
      src.setPixel(t, 160, img.ColorRgb8(240, 240, 240));
    }
    for (var t = 40; t <= 160; t++) {
      src.setPixel(30, t, img.ColorRgb8(240, 240, 240));
      src.setPixel(270, t, img.ColorRgb8(240, 240, 240));
    }

    final rgb = loadRgbImage(Uint8List.fromList(img.encodePng(src)), maxDim: 900);
    expect(layoutMapPanelLeftPx(rgb), 0);
    expect(detectHloSatellitePanelOnlyRgb(rgb), isTrue);
  });
}
