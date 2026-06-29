import { interiorMask, loadRgbImage, toUv } from './boundary-detector.js';
import type { CvDetection, UvPoint } from './types.js';

function isWater(r: number, g: number, b: number): boolean {
  return b > 90 && b > r + 15 && b > g + 5 && g < 180;
}

function isVegetation(r: number, g: number, b: number): boolean {
  return g > 80 && g > r + 10 && g > b + 5 && r < 160;
}

export async function detectWaterAndVegetation(
  buffer: Buffer,
  boundaryUv: UvPoint[]
): Promise<{
  waterBodies: CvDetection[];
  canalCrossings: CvDetection[];
  vegetationPatches: CvDetection[];
  landmarks: CvDetection[];
  landmarkConfidence: number;
}> {
  const img = await loadRgbImage(buffer);
  const mask = boundaryUv.length >= 3 ? interiorMask(img, boundaryUv) : new Array(img.width * img.height).fill(true);
  const GRID = 12;
  const cellW = img.width / GRID;
  const cellH = img.height / GRID;

  const waterBodies: CvDetection[] = [];
  const vegetationPatches: CvDetection[] = [];

  for (let gy = 0; gy < GRID; gy++) {
    for (let gx = 0; gx < GRID; gx++) {
      let water = 0;
      let veg = 0;
      let total = 0;
      const x0 = Math.floor(gx * cellW);
      const y0 = Math.floor(gy * cellH);
      const x1 = Math.min(img.width, Math.floor((gx + 1) * cellW));
      const y1 = Math.min(img.height, Math.floor((gy + 1) * cellH));

      for (let y = y0; y < y1; y += 3) {
        for (let x = x0; x < x1; x += 3) {
          if (!mask[y * img.width + x]) continue;
          total++;
          const i = (y * img.width + x) * 3;
          const r = img.data[i];
          const g = img.data[i + 1];
          const b = img.data[i + 2];
          if (isWater(r, g, b)) water++;
          if (isVegetation(r, g, b)) veg++;
        }
      }
      if (total < 3) continue;
      const cx = (gx + 0.5) * cellW;
      const cy = (gy + 0.5) * cellH;
      const uv = toUv(img, cx, cy);

      if (water / total > 0.35) {
        waterBodies.push({
          id: `w${waterBodies.length + 1}`,
          label: 'Canal / water body',
          sketchX: uv.x,
          sketchY: uv.y,
          confidence: Math.min(0.9, 0.5 + water / total),
        });
      }
      if (veg / total > 0.4) {
        vegetationPatches.push({
          id: `veg${vegetationPatches.length + 1}`,
          label: 'Vegetation patch',
          sketchX: uv.x,
          sketchY: uv.y,
          confidence: Math.min(0.85, 0.45 + veg / total),
        });
      }
    }
  }

  const canalCrossings: CvDetection[] = waterBodies.slice(0, 5).map((w, i) => ({
    id: `cc${i + 1}`,
    label: 'Canal crossing',
    sketchX: w.sketchX,
    sketchY: w.sketchY,
    confidence: w.confidence * 0.85,
  }));

  const landmarks: CvDetection[] = [];
  if (waterBodies.length > 0) {
    landmarks.push({ ...waterBodies[0], id: 'lm1', label: 'Water feature', confidence: 0.65 });
  }

  return {
    waterBodies: waterBodies.slice(0, 10),
    canalCrossings,
    vegetationPatches: vegetationPatches.slice(0, 15),
    landmarks,
    landmarkConfidence: landmarks.length > 0 ? 0.68 : 0.4,
  };
}
