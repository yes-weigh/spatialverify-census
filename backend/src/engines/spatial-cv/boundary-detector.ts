import { convexHull, dist, grayscale, loadRgbImage, simplifyPolygon, toUv, type RgbImage } from './image-utils.js';
import type { UvPoint } from './types.js';

function isBoundaryColor(r: number, g: number, b: number): boolean {
  if (r > 165 && g < 110 && b < 110 && r - Math.max(g, b) > 55) return true;
  if (r > 190 && g > 150 && b < 130 && r - b > 40) return true;
  if (r > 170 && b > 90 && g < 130 && Math.abs(r - b) < 80) return true;
  return false;
}

function boundaryMask(img: RgbImage): boolean[] {
  const mask = new Array(img.width * img.height).fill(false);
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      const i = (y * img.width + x) * 3;
      mask[y * img.width + x] = isBoundaryColor(img.data[i], img.data[i + 1], img.data[i + 2]);
    }
  }
  return mask;
}

function rayCastBoundary(
  img: RgbImage,
  mask: boolean[],
  cx: number,
  cy: number,
  rays = 48
): { x: number; y: number }[] {
  const points: { x: number; y: number }[] = [];
  const maxR = Math.hypot(img.width, img.height);

  for (let i = 0; i < rays; i++) {
    const angle = (2 * Math.PI * i) / rays;
    const dx = Math.cos(angle);
    const dy = Math.sin(angle);
    let found: { x: number; y: number } | null = null;

    for (let r = 8; r < maxR; r += 2) {
      const x = Math.round(cx + dx * r);
      const y = Math.round(cy + dy * r);
      if (x < 0 || y < 0 || x >= img.width || y >= img.height) break;
      if (mask[y * img.width + x]) found = { x, y };
    }
    if (found) points.push(found);
  }

  if (points.length < 6) return [];
  const hull = convexHull(points);
  return simplifyPolygon(hull, Math.max(img.width, img.height) * 0.015);
}

function maskCentroid(mask: boolean[], w: number, h: number): { x: number; y: number } {
  let sx = 0;
  let sy = 0;
  let n = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (mask[y * w + x]) {
        sx += x;
        sy += y;
        n++;
      }
    }
  }
  if (n === 0) return { x: w / 2, y: h / 2 };
  return { x: sx / n, y: sy / n };
}

function polygonAreaPx(ring: { x: number; y: number }[]): number {
  let area = 0;
  for (let i = 0; i < ring.length; i++) {
    const j = (i + 1) % ring.length;
    area += ring[i].x * ring[j].y - ring[j].x * ring[i].y;
  }
  return Math.abs(area) / 2;
}

export async function detectBoundary(buffer: Buffer): Promise<{
  polygon: UvPoint[];
  confidence: number;
  diagnostics: Record<string, number>;
}> {
  const img = await loadRgbImage(buffer);
  const mask = boundaryMask(img);
  const boundaryPixels = mask.filter(Boolean).length;
  const total = img.width * img.height;
  const ratio = boundaryPixels / total;

  const centroid = maskCentroid(mask, img.width, img.height);
  let ring = rayCastBoundary(img, mask, centroid.x, centroid.y);

  if (ring.length < 3) {
    const xs: number[] = [];
    const ys: number[] = [];
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        if (mask[y * img.width + x]) {
          xs.push(x);
          ys.push(y);
        }
      }
    }
    if (xs.length > 10) {
      ring = [
        { x: Math.min(...xs), y: Math.min(...ys) },
        { x: Math.max(...xs), y: Math.min(...ys) },
        { x: Math.max(...xs), y: Math.max(...ys) },
        { x: Math.min(...xs), y: Math.max(...ys) },
      ];
    }
  }

  const polygon = ring.map((p) => toUv(img, p.x, p.y));
  const area = polygonAreaPx(ring);
  const perimeter = ring.reduce((sum, p, i) => {
    const n = ring[(i + 1) % ring.length];
    return sum + dist(p, n);
  }, 0);
  const compactness = area > 0 ? (4 * Math.PI * area) / (perimeter * perimeter) : 0;

  let confidence = 0.5;
  if (ratio > 0.002 && ratio < 0.08) confidence += 0.2;
  if (polygon.length >= 4) confidence += 0.15;
  if (compactness > 0.15 && compactness < 0.85) confidence += 0.1;
  if (boundaryPixels > 200) confidence += 0.05;
  confidence = Math.min(0.98, confidence);

  return {
    polygon,
    confidence,
    diagnostics: { boundaryPixelRatio: ratio, boundaryPoints: polygon.length, compactness, boundaryPixels },
  };
}

/** Interior mask — pixels inside detected boundary, excluding boundary line itself. */
export function interiorMask(img: RgbImage, boundaryUv: UvPoint[]): boolean[] {
  const ring = boundaryUv.map((p) => ({
    x: p.x * img.width,
    y: p.y * img.height,
  }));
  const mask = new Array(img.width * img.height).fill(false);

  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      let inside = false;
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const xi = ring[i].x;
        const yi = ring[i].y;
        const xj = ring[j].x;
        const yj = ring[j].y;
        if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi + 1e-9) + xi) {
          inside = !inside;
        }
      }
      mask[y * img.width + x] = inside;
    }
  }
  return mask;
}

export { loadRgbImage, grayscale, toUv, type RgbImage };
