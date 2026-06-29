import 'dart:math' as math;

import 'spatial_cv_image.dart';
import 'spatial_cv_types.dart';

const _grid = 14;

double _cellTextureScore(RgbImage img, List<bool> mask, int gx, int gy, double cellW, double cellH) {
  final values = <double>[];
  final x0 = (gx * cellW).floor();
  final y0 = (gy * cellH).floor();
  final x1 = math.min(img.width, ((gx + 1) * cellW).floor());
  final y1 = math.min(img.height, ((gy + 1) * cellH).floor());

  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      if (!mask[y * img.width + x]) continue;
      final i = (y * img.width + x) * 3;
      values.add(grayscale(img.data[i], img.data[i + 1], img.data[i + 2]));
    }
  }
  if (values.length < 4) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
  final edge = values.where((v) {
    final idx = values.indexOf(v);
    return idx > 0 && (v - values[idx - 1]).abs() > 18;
  }).length;
  if (mean < 40 || mean > 220) return 0;
  return variance * 0.01 + edge * 0.5;
}

({List<CvDetection> targets, double confidence}) detectObservationTargets(RgbImage img, List<UvPoint> boundaryUv) {
  final mask = boundaryUv.length >= 3 ? interiorMask(img, boundaryUv) : List<bool>.filled(img.width * img.height, true);

  final cellW = img.width / _grid;
  final cellH = img.height / _grid;
  final scored = <({int gx, int gy, double score})>[];

  for (var gy = 0; gy < _grid; gy++) {
    for (var gx = 0; gx < _grid; gx++) {
      final score = _cellTextureScore(img, mask, gx, gy, cellW, cellH);
      if (score > 2.5) scored.add((gx: gx, gy: gy, score: score));
    }
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  final targets = <CvDetection>[];
  const minDist = 0.06;

  for (final cell in scored) {
    final cx = (cell.gx + 0.5) * cellW;
    final cy = (cell.gy + 0.5) * cellH;
    final uv = toUv(img, cx, cy);
    final tooClose = targets.any((t) => math.sqrt((t.sketchX - uv.x) * (t.sketchX - uv.x) + (t.sketchY - uv.y) * (t.sketchY - uv.y)) < minDist);
    if (tooClose) continue;
    targets.add(CvDetection(
      id: 'ot${targets.length + 1}',
      label: 'Observation target',
      sketchX: uv.x,
      sketchY: uv.y,
      confidence: math.min(0.92, 0.55 + cell.score * 0.04),
    ));
    if (targets.length >= 24) break;
  }

  final confidence = targets.length >= 8
      ? 0.85
      : targets.length >= 3
          ? 0.72
          : targets.isNotEmpty
              ? 0.58
              : 0.35;

  return (targets: targets, confidence: confidence);
}
