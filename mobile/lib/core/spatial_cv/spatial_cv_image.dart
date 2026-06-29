import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'spatial_cv_types.dart';

/// Census HLO PDF sidebar width (metadata panel on the left of the layout sheet).
const kHloLayoutSidebarFraction = 0.28;

class RgbImage {
  RgbImage({required this.width, required this.height, required this.data});
  final int width;
  final int height;
  final Uint8List data;
}

RgbImage loadRgbImage(Uint8List bytes, {int maxDim = 900}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Could not decode map image');

  var width = decoded.width;
  var height = decoded.height;
  final scale = math.min(1.0, maxDim / math.max(width, height));
  final img.Image resized;
  if (scale < 1) {
    resized = img.copyResize(
      decoded,
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  } else {
    resized = decoded;
  }

  width = resized.width;
  height = resized.height;
  final data = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = resized.getPixel(x, y);
      final i = (y * width + x) * 3;
      data[i] = p.r.toInt();
      data[i + 1] = p.g.toInt();
      data[i + 2] = p.b.toInt();
    }
  }
  return RgbImage(width: width, height: height, data: data);
}

bool isNearWhiteLayoutPixel(img.Pixel p, {int threshold = 247}) =>
    p.r.toInt() >= threshold && p.g.toInt() >= threshold && p.b.toInt() >= threshold;

bool _isNearWhiteRgb(RgbImage image, int x, int y, {int threshold = 247}) {
  final i = (y * image.width + x) * 3;
  final r = image.data[i];
  final g = image.data[i + 1];
  final b = image.data[i + 2];
  return r >= threshold && g >= threshold && b >= threshold;
}

/// True when the image is already cropped to the satellite panel (no metadata sidebar).
bool detectHloSatellitePanelOnly(img.Image image) {
  final stripWidth = (image.width * 0.14).round().clamp(8, 120);
  var samples = 0;
  var whiteSamples = 0;
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < stripWidth; x += 4) {
      samples++;
      if (isNearWhiteLayoutPixel(image.getPixel(x, y))) whiteSamples++;
    }
  }
  if (samples == 0) return false;
  return whiteSamples / samples < 0.62;
}

bool detectHloSatellitePanelOnlyRgb(RgbImage image) {
  final stripWidth = (image.width * 0.14).round().clamp(8, 120);
  var samples = 0;
  var whiteSamples = 0;
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < stripWidth; x += 4) {
      samples++;
      if (_isNearWhiteRgb(image, x, y)) whiteSamples++;
    }
  }
  if (samples == 0) return false;
  return whiteSamples / samples < 0.62;
}

/// Left column to skip when scanning the satellite panel (0 after import crop).
int layoutMapPanelLeftPx(RgbImage image) {
  if (detectHloSatellitePanelOnlyRgb(image)) return 0;
  return (image.width * kHloLayoutSidebarFraction).round().clamp(0, image.width - 1);
}

/// Default flood-fill seed when OCR block center is unavailable.
({double x, double y}) defaultHloBlockCenterPx(RgbImage image) {
  final panelLeft = layoutMapPanelLeftPx(image);
  return (
    x: panelLeft + (image.width - panelLeft) * 0.58,
    y: image.height * 0.48,
  );
}

/// Bounding box of non-white content on a layout sheet (before sidebar crop).
({int left, int top, int width, int height})? detectLayoutContentBounds(
  img.Image src, {
  int threshold = 247,
  int minSpan = 40,
}) {
  var minX = src.width;
  var minY = src.height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (isNearWhiteLayoutPixel(src.getPixel(x, y), threshold: threshold)) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX <= minX || maxY <= minY) return null;
  if (maxX - minX + 1 < minSpan || maxY - minY + 1 < minSpan) return null;

  minX = math.max(0, minX - 1);
  minY = math.max(0, minY - 1);
  maxX = math.min(src.width - 1, maxX + 1);
  maxY = math.min(src.height - 1, maxY + 1);

  final width = maxX - minX + 1;
  final height = maxY - minY + 1;
  if (width == src.width && height == src.height) {
    return (left: 0, top: 0, width: src.width, height: src.height);
  }
  return (left: minX, top: minY, width: width, height: height);
}

/// Crops to the bounding box of non-white content (removes PDF page margins).
img.Image trimWhiteMargins(
  img.Image src, {
  int threshold = 247,
  int minSpan = 40,
}) {
  final bounds = detectLayoutContentBounds(src, threshold: threshold, minSpan: minSpan);
  if (bounds == null) return src;
  if (bounds.width == src.width && bounds.height == src.height) return src;
  return img.copyCrop(
    src,
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
}

img.Image cropHloSatellitePanel(img.Image src) {
  final minWidth = 80;
  final panelLeft = (src.width * kHloLayoutSidebarFraction).round().clamp(0, src.width - minWidth);
  if (panelLeft < 8) return src;
  return img.copyCrop(
    src,
    x: panelLeft,
    y: 0,
    width: src.width - panelLeft,
    height: src.height,
  );
}

/// Trims page margins only — keeps left metadata panel and form borders.
Uint8List prepareFormSheetImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final trimmed = trimWhiteMargins(decoded);
  return Uint8List.fromList(img.encodePng(trimmed));
}

/// Optional crop — trims page margins and removes the left legend column for satellite overlay.
Uint8List prepareLayoutMapImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  var image = trimWhiteMargins(decoded);
  if (!detectHloSatellitePanelOnly(image)) {
    image = cropHloSatellitePanel(image);
    image = trimWhiteMargins(image);
  }

  return Uint8List.fromList(img.encodePng(image));
}

UvPoint toUv(RgbImage image, double x, double y) => UvPoint(x / image.width, y / image.height);

double grayscale(int r, int g, int b) => 0.299 * r + 0.587 * g + 0.114 * b;

double distPx(double x1, double y1, double x2, double y2) =>
    math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));

List<({double x, double y})> convexHull(List<({double x, double y})> points) {
  if (points.length < 3) return points;
  final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x) != 0 ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

  double cross(({double x, double y}) o, ({double x, double y}) a, ({double x, double y}) b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <({double x, double y})>[];
  for (final p in sorted) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <({double x, double y})>[];
  for (var i = sorted.length - 1; i >= 0; i--) {
    final p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  upper.removeLast();
  lower.removeLast();
  return [...lower, ...upper];
}

List<({double x, double y})> simplifyPolygon(List<({double x, double y})> points, double epsilon) {
  if (points.length <= 3) return points;

  double sqDist(({double x, double y}) p, ({double x, double y}) a, ({double x, double y}) b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    if (dx == 0 && dy == 0) {
      final d = distPx(p.x, p.y, a.x, a.y);
      return d * d;
    }
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    final projX = a.x + t * dx;
    final projY = a.y + t * dy;
    final d = distPx(p.x, p.y, projX, projY);
    return d * d;
  }

  var maxSq = 0.0;
  var idx = 0;
  for (var i = 1; i < points.length - 1; i++) {
    final d = sqDist(points[i], points.first, points.last);
    if (d > maxSq) {
      maxSq = d;
      idx = i;
    }
  }

  if (maxSq > epsilon * epsilon) {
    final left = simplifyPolygon(points.sublist(0, idx + 1), epsilon);
    final right = simplifyPolygon(points.sublist(idx), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [points.first, points.last];
}

bool interiorMaskAt(RgbImage image, List<UvPoint> boundaryUv, int x, int y) {
  final ring = boundaryUv.map((p) => (x: p.x * image.width, y: p.y * image.height)).toList();
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].x;
    final yi = ring[i].y;
    final xj = ring[j].x;
    final yj = ring[j].y;
    if ((yi > y) != (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi + 1e-9) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

List<bool> interiorMask(RgbImage image, List<UvPoint> boundaryUv) {
  final mask = List<bool>.filled(image.width * image.height, false);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      mask[y * image.width + x] = interiorMaskAt(image, boundaryUv, x, y);
    }
  }
  return mask;
}
