import { haversineMeters } from './geo.js';

export interface ControlPoint {
  id: string;
  label: string;
  sketchX: number;
  sketchY: number;
  lat: number;
  lng: number;
}

export interface SketchPoint {
  x: number;
  y: number;
}

/** Least-squares affine: lat = a*x + b*y + c, lng = d*x + e*y + f */
export function computeAffineTransform(points: ControlPoint[]): { matrix: number[]; rmsErrorMeters: number } {
  if (points.length < 3) throw new Error('At least 3 control points required');

  const latCoeffs = solvePlane(points.map((p) => ({ x: p.sketchX, y: p.sketchY, v: p.lat })));
  const lngCoeffs = solvePlane(points.map((p) => ({ x: p.sketchX, y: p.sketchY, v: p.lng })));
  const matrix = [...latCoeffs, ...lngCoeffs];

  let sumSq = 0;
  for (const p of points) {
    const pred = applyAffine(matrix, p.sketchX, p.sketchY);
    const err = haversineMeters(p.lat, p.lng, pred.lat, pred.lng);
    sumSq += err * err;
  }

  return { matrix, rmsErrorMeters: Math.sqrt(sumSq / points.length) };
}

function solvePlane(samples: Array<{ x: number; y: number; v: number }>): [number, number, number] {
  let sxx = 0, syy = 0, sxy = 0, sx = 0, sy = 0, n = 0;
  let svx = 0, svy = 0, sv = 0;
  for (const p of samples) {
    sxx += p.x * p.x;
    syy += p.y * p.y;
    sxy += p.x * p.y;
    sx += p.x;
    sy += p.y;
    n += 1;
    svx += p.x * p.v;
    svy += p.y * p.v;
    sv += p.v;
  }
  const m = [
    [sxx, sxy, sx],
    [sxy, syy, sy],
    [sx, sy, n],
  ];
  const b = [svx, svy, sv];
  const sol = solve3(m, b);
  return [sol[0], sol[1], sol[2]];
}

function solve3(a: number[][], b: number[]): number[] {
  const aug = a.map((row, i) => [...row, b[i]]);
  for (let col = 0; col < 3; col++) {
    let pivot = col;
    for (let row = col + 1; row < 3; row++) {
      if (Math.abs(aug[row][col]) > Math.abs(aug[pivot][col])) pivot = row;
    }
    [aug[col], aug[pivot]] = [aug[pivot], aug[col]];
    const div = aug[col][col] || 1e-12;
    for (let j = col; j <= 3; j++) aug[col][j] /= div;
    for (let row = 0; row < 3; row++) {
      if (row === col) continue;
      const factor = aug[row][col];
      for (let j = col; j <= 3; j++) aug[row][j] -= factor * aug[col][j];
    }
  }
  return [aug[0][3], aug[1][3], aug[2][3]];
}

export function applyAffine(matrix: number[], x: number, y: number): { lat: number; lng: number } {
  const [a, b, c, d, e, f] = matrix;
  return { lat: a * x + b * y + c, lng: d * x + e * y + f };
}

export function transformSketchBoundary(
  matrix: number[],
  sketchBoundary: SketchPoint[]
): Array<{ lat: number; lng: number }> {
  return sketchBoundary.map((p) => applyAffine(matrix, p.x, p.y));
}

export function alignmentQuality(rmsMeters: number): 'excellent' | 'good' | 'needs_review' {
  if (rmsMeters < 10) return 'excellent';
  if (rmsMeters < 25) return 'good';
  return 'needs_review';
}

export function sketchPolygonArea(sketchBoundary: SketchPoint[]): number {
  if (sketchBoundary.length < 3) return 0;
  let area = 0;
  for (let i = 0; i < sketchBoundary.length; i++) {
    const j = (i + 1) % sketchBoundary.length;
    area += sketchBoundary[i].x * sketchBoundary[j].y;
    area -= sketchBoundary[j].x * sketchBoundary[i].y;
  }
  return Math.abs(area) / 2;
}
