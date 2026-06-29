import { grayscale, interiorMask, loadRgbImage, toUv, type RgbImage } from './boundary-detector.js';
import type { CvDetection, UvPoint } from './types.js';

const GRID = 14;

function cellTextureScore(img: RgbImage, mask: boolean[], gx: number, gy: number, cellW: number, cellH: number): number {
  const values: number[] = [];
  const x0 = Math.floor(gx * cellW);
  const y0 = Math.floor(gy * cellH);
  const x1 = Math.min(img.width, Math.floor((gx + 1) * cellW));
  const y1 = Math.min(img.height, Math.floor((gy + 1) * cellH));

  for (let y = y0; y < y1; y += 2) {
    for (let x = x0; x < x1; x += 2) {
      if (!mask[y * img.width + x]) continue;
      const i = (y * img.width + x) * 3;
      values.push(grayscale(img.data[i], img.data[i + 1], img.data[i + 2]));
    }
  }
  if (values.length < 4) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance = values.reduce((a, v) => a + (v - mean) ** 2, 0) / values.length;
  const edge = values.filter((v, idx) => idx > 0 && Math.abs(v - values[idx - 1]) > 18).length;
  if (mean < 40 || mean > 220) return 0;
  return variance * 0.01 + edge * 0.5;
}

export async function detectObservationTargets(
  buffer: Buffer,
  boundaryUv: UvPoint[]
): Promise<{ targets: CvDetection[]; confidence: number }> {
  const img = await loadRgbImage(buffer);
  const mask = boundaryUv.length >= 3 ? interiorMask(img, boundaryUv) : new Array(img.width * img.height).fill(true);

  const cellW = img.width / GRID;
  const cellH = img.height / GRID;
  const scored: { gx: number; gy: number; score: number }[] = [];

  for (let gy = 0; gy < GRID; gy++) {
    for (let gx = 0; gx < GRID; gx++) {
      const score = cellTextureScore(img, mask, gx, gy, cellW, cellH);
      if (score > 2.5) scored.push({ gx, gy, score });
    }
  }

  scored.sort((a, b) => b.score - a.score);
  const targets: CvDetection[] = [];
  const minDist = 0.06;

  for (const cell of scored) {
    const cx = (cell.gx + 0.5) * cellW;
    const cy = (cell.gy + 0.5) * cellH;
    const uv = toUv(img, cx, cy);
    const tooClose = targets.some(
      (t) => Math.hypot(t.sketchX - uv.x, t.sketchY - uv.y) < minDist
    );
    if (tooClose) continue;
    targets.push({
      id: `ot${targets.length + 1}`,
      label: 'Observation target',
      sketchX: uv.x,
      sketchY: uv.y,
      confidence: Math.min(0.92, 0.55 + cell.score * 0.04),
    });
    if (targets.length >= 120) break;
  }

  const confidence =
    targets.length >= 8 ? 0.85 : targets.length >= 3 ? 0.72 : targets.length > 0 ? 0.58 : 0.35;

  return { targets, confidence };
}
