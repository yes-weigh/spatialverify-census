import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// True when ([u], [v]) lies inside a closed UV polygon (image coords, v down).
bool pointInUvRing(double u, double v, List<({double x, double y})> ring) {
  if (ring.length < 3) return true;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].x;
    final yi = ring[i].y;
    final xj = ring[j].x;
    final yj = ring[j].y;
    final intersects = (yi > v) != (yj > v) && u < (xj - xi) * (v - yi) / (yj - yi) + xi;
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Pixels outside [uvRing] become fully transparent; overlay bounds stay unchanged.
Uint8List maskLayoutPngOutsideBoundary(
  Uint8List pngBytes,
  List<({double x, double y})> uvRing,
) {
  if (uvRing.length < 3) return pngBytes;

  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) return pngBytes;

  final w = decoded.width;
  final h = decoded.height;
  if (w <= 0 || h <= 0) return pngBytes;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x / w;
      final v = y / h;
      if (!pointInUvRing(u, v, uvRing)) {
        final pixel = decoded.getPixel(x, y);
        decoded.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, 0);
      }
    }
  }

  return Uint8List.fromList(img.encodePng(decoded));
}
