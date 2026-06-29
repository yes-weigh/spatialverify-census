import 'dart:collection';
import 'dart:math' as math;

import 'spatial_cv_image.dart';
import 'spatial_cv_types.dart';

/// Douglas–Peucker tolerance in **pixels** (not image fraction).
const _contourSimplifyEpsilonPx = 3.0;

bool _isThickWhiteBoundary(int r, int g, int b) {
  final minC = math.min(r, math.min(g, b));
  final maxC = math.max(r, math.max(g, b));
  return minC > 205 && maxC - minC < 40;
}

bool _get(List<bool> grid, int width, int x, int y) {
  if (x < 0 || y < 0) return false;
  return grid[y * width + x];
}

int _neighbors8(List<bool> grid, int width, int height, int x, int y) {
  var count = 0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      if (x + dx < 0 || y + dy < 0 || x + dx >= width || y + dy >= height) continue;
      if (grid[(y + dy) * width + (x + dx)]) count++;
    }
  }
  return count;
}

int _transitions(List<bool> grid, int width, int x, int y) {
  const offsets = [
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
  ];
  var transitions = 0;
  for (var i = 0; i < offsets.length - 1; i++) {
    final a = _get(grid, width, x + offsets[i].$1, y + offsets[i].$2);
    final b = _get(grid, width, x + offsets[i + 1].$1, y + offsets[i + 1].$2);
    if (a != b) transitions++;
  }
  return transitions;
}

bool _zhangSuenStep1(List<bool> grid, int width, int height, int x, int y) {
  if (!_get(grid, width, x, y)) return false;
  final bp = _neighbors8(grid, width, height, x, y);
  if (bp < 2 || bp > 6) return false;
  if (_transitions(grid, width, x, y) != 1) return false;
  if (_get(grid, width, x, y + 1) && _get(grid, width, x + 1, y) && _get(grid, width, x, y - 1)) {
    return false;
  }
  if (_get(grid, width, x + 1, y) && _get(grid, width, x, y - 1) && _get(grid, width, x - 1, y)) {
    return false;
  }
  return true;
}

bool _zhangSuenStep2(List<bool> grid, int width, int height, int x, int y) {
  if (!_get(grid, width, x, y)) return false;
  final bp = _neighbors8(grid, width, height, x, y);
  if (bp < 2 || bp > 6) return false;
  if (_transitions(grid, width, x, y) != 1) return false;
  if (_get(grid, width, x, y + 1) && _get(grid, width, x + 1, y) && _get(grid, width, x - 1, y)) {
    return false;
  }
  if (_get(grid, width, x, y + 1) && _get(grid, width, x, y - 1) && _get(grid, width, x - 1, y)) {
    return false;
  }
  return true;
}

/// Reduce thick white strokes to a one-pixel-wide skeleton.
List<bool> _skeletonize(List<bool> grid, int width, int height) {
  var current = List<bool>.from(grid);
  var changed = true;

  while (changed) {
    changed = false;
    final pass1 = <int>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (_zhangSuenStep1(current, width, height, x, y)) pass1.add(y * width + x);
      }
    }
    for (final i in pass1) {
      current[i] = false;
      changed = true;
    }

    final pass2 = <int>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (_zhangSuenStep2(current, width, height, x, y)) pass2.add(y * width + x);
      }
    }
    for (final i in pass2) {
      current[i] = false;
      changed = true;
    }
  }

  return current;
}

/// White boundary pixels only — ignores red/orange census annotation lines.
List<bool> _whiteBoundaryMask(RgbImage img) {
  final panelLeft = layoutMapPanelLeftPx(img);
  final mask = List<bool>.filled(img.width * img.height, false);
  for (var y = 0; y < img.height; y++) {
    for (var x = panelLeft; x < img.width; x++) {
      final i = (y * img.width + x) * 3;
      final r = img.data[i];
      final g = img.data[i + 1];
      final b = img.data[i + 2];
      mask[y * img.width + x] = _isThickWhiteBoundary(r, g, b);
    }
  }
  return mask;
}

({double x, double y}) _defaultBlockCenter(RgbImage img) => defaultHloBlockCenterPx(img);

({int x, int y}) _seedPixel(RgbImage img, UvPoint? blockCenterUv) {
  final center = blockCenterUv != null
      ? (x: blockCenterUv.x * img.width, y: blockCenterUv.y * img.height)
      : _defaultBlockCenter(img);
  return (x: center.x.round().clamp(0, img.width - 1), y: center.y.round().clamp(0, img.height - 1));
}

/// If OCR lands on the white ring, walk outward to the nearest interior pixel.
({int x, int y})? _resolveFillSeed(List<bool> wall, int width, int height, int sx, int sy) {
  if (!_get(wall, width, sx, sy)) return (x: sx, y: sy);

  for (var radius = 1; radius <= 40; radius++) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        if (dx.abs() != radius && dy.abs() != radius) continue;
        final x = sx + dx;
        final y = sy + dy;
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        if (!_get(wall, width, x, y)) return (x: x, y: y);
      }
    }
  }
  return null;
}

/// Paint-bucket fill: expand from seed until white boundary walls are hit.
List<bool> _floodFillInterior(List<bool> wall, int width, int height, int sx, int sy) {
  final interior = List<bool>.filled(width * height, false);
  if (sx < 0 || sy < 0 || sx >= width || sy >= height) return interior;
  if (_get(wall, width, sx, sy)) return interior;

  final queue = Queue<int>()..add(sy * width + sx);
  interior[sy * width + sx] = true;

  while (queue.isNotEmpty) {
    final idx = queue.removeFirst();
    final x = idx % width;
    final y = idx ~/ width;

    for (final delta in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + delta.$1;
      final ny = y + delta.$2;
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      final nIdx = ny * width + nx;
      if (interior[nIdx] || _get(wall, width, nx, ny)) continue;
      interior[nIdx] = true;
      queue.add(nIdx);
    }
  }

  return interior;
}

bool _isContourPixel(List<bool> interior, int width, int height, int x, int y) {
  if (!_get(interior, width, x, y)) return false;
  if (x == 0 || y == 0 || x == width - 1 || y == height - 1) return true;
  return !_get(interior, width, x - 1, y) ||
      !_get(interior, width, x + 1, y) ||
      !_get(interior, width, x, y - 1) ||
      !_get(interior, width, x, y + 1);
}

/// Moore-neighbour outer contour of a filled region (OpenCV findContours equivalent).
List<({double x, double y})> _traceOuterContour(List<bool> interior, int width, int height) {
  var startX = -1;
  var startY = -1;
  outer:
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (_isContourPixel(interior, width, height, x, y)) {
        startX = x;
        startY = y;
        break outer;
      }
    }
  }
  if (startX < 0) return [];

  const dirs = [
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
  ];

  final contour = <({double x, double y})>[];
  var x = startX;
  var y = startY;
  var dir = 7;
  var guard = 0;
  const maxSteps = 200000;

  do {
    contour.add((x: x.toDouble(), y: y.toDouble()));
    var found = false;
    for (var i = 0; i < 8; i++) {
      final checkDir = (dir + i) % 8;
      final nx = x + dirs[checkDir].$1;
      final ny = y + dirs[checkDir].$2;
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      if (_isContourPixel(interior, width, height, nx, ny)) {
        x = nx;
        y = ny;
        dir = (checkDir + 6) % 8;
        found = true;
        break;
      }
    }
    if (!found) break;
    guard++;
  } while ((x != startX || y != startY || contour.length < 4) && guard < maxSteps);

  if (contour.length >= 2 &&
      contour.first.x == contour.last.x &&
      contour.first.y == contour.last.y) {
    contour.removeLast();
  }

  return contour;
}

double _polygonAreaPx(List<({double x, double y})> ring) {
  if (ring.length < 3) return 0;
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    area += ring[i].x * ring[j].y - ring[j].x * ring[i].y;
  }
  return area.abs() / 2;
}

({List<UvPoint> polygon, double confidence, Map<String, dynamic> diagnostics}) detectBoundary(
  RgbImage img, {
  UvPoint? blockCenterUv,
}) {
  final panelLeft = layoutMapPanelLeftPx(img);
  final panelPixels = (img.width - panelLeft) * img.height;

  final whiteMask = _whiteBoundaryMask(img);
  final whiteCount = whiteMask.where((v) => v).length;
  final whiteRatio = whiteCount / panelPixels;

  final skeleton = _skeletonize(whiteMask, img.width, img.height);
  final wall = skeleton;

  final seedPx = _seedPixel(img, blockCenterUv);
  final fillSeed = _resolveFillSeed(wall, img.width, img.height, seedPx.x, seedPx.y);
  if (fillSeed == null) {
    return (
      polygon: const <UvPoint>[],
      confidence: 0,
      diagnostics: {
        'method': 'flood_fill_contour',
        'error': 'could_not_resolve_seed',
        'whiteBoundaryPixelRatio': whiteRatio,
      },
    );
  }

  final interior = _floodFillInterior(wall, img.width, img.height, fillSeed.x, fillSeed.y);
  final filledCount = interior.where((v) => v).length;
  final fillRatio = filledCount / panelPixels;

  if (fillRatio < 0.015 || fillRatio > 0.45) {
    return (
      polygon: const <UvPoint>[],
      confidence: 0,
      diagnostics: {
        'method': 'flood_fill_contour',
        'error': 'implausible_fill_ratio',
        'interiorFillRatio': fillRatio,
        'whiteBoundaryPixelRatio': whiteRatio,
        'seedPx': {'x': fillSeed.x, 'y': fillSeed.y},
      },
    );
  }

  var contour = _traceOuterContour(interior, img.width, img.height);
  if (contour.length >= 4) {
    contour = simplifyPolygon(contour, _contourSimplifyEpsilonPx);
  }

  final polygon = contour.map((p) => toUv(img, p.x, p.y)).toList();
  final areaPx = _polygonAreaPx(contour);

  var confidence = 0.35;
  if (whiteRatio > 0.0005 && whiteRatio < 0.08) confidence += 0.15;
  if (fillRatio > 0.03 && fillRatio < 0.5) confidence += 0.2;
  if (polygon.length >= 4) confidence += 0.15;
  if (blockCenterUv != null) confidence += 0.1;
  if (areaPx > 0) confidence += 0.05;
  confidence = math.min(0.98, confidence);

  return (
    polygon: polygon,
    confidence: confidence,
    diagnostics: {
      'method': 'flood_fill_contour',
      'boundaryPoints': polygon.length,
      'whiteBoundaryPixelRatio': whiteRatio,
      'interiorFillRatio': fillRatio,
      'interiorAreaPx': areaPx.round(),
      'simplifyEpsilonPx': _contourSimplifyEpsilonPx,
      'seedPx': {'x': fillSeed.x, 'y': fillSeed.y},
      'blockCenterUv': blockCenterUv == null ? null : {'x': blockCenterUv.x, 'y': blockCenterUv.y},
      'ocrAnchored': blockCenterUv != null,
    },
  );
}
