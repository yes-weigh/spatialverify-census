import sharp from 'sharp';

export interface RgbImage {
  width: number;
  height: number;
  data: Uint8Array;
}

export async function loadRgbImage(buffer: Buffer, maxDim = 900): Promise<RgbImage> {
  const pipeline = sharp(buffer).rotate().ensureAlpha();
  const meta = await pipeline.metadata();
  const w = meta.width ?? 800;
  const h = meta.height ?? 600;
  const scale = Math.min(1, maxDim / Math.max(w, h));
  const width = Math.max(1, Math.round(w * scale));
  const height = Math.max(1, Math.round(h * scale));

  const raw = await pipeline
    .resize(width, height, { fit: 'inside' })
    .removeAlpha()
    .raw()
    .toBuffer();

  return { width, height, data: new Uint8Array(raw) };
}

export function pixelAt(img: RgbImage, x: number, y: number): [number, number, number] {
  const cx = Math.max(0, Math.min(img.width - 1, Math.round(x)));
  const cy = Math.max(0, Math.min(img.height - 1, Math.round(y)));
  const i = (cy * img.width + cx) * 3;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
}

export function toUv(img: RgbImage, x: number, y: number): { x: number; y: number } {
  return { x: x / img.width, y: y / img.height };
}

export function grayscale(r: number, g: number, b: number): number {
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

export function dist(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** Douglas–Peucker simplification in pixel space. */
export function simplifyPolygon(points: { x: number; y: number }[], epsilon: number): { x: number; y: number }[] {
  if (points.length <= 3) return points;

  const sqDist = (p: { x: number; y: number }, a: { x: number; y: number }, b: { x: number; y: number }) => {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    if (dx === 0 && dy === 0) return dist(p, a) ** 2;
    const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)));
    const proj = { x: a.x + t * dx, y: a.y + t * dy };
    return dist(p, proj) ** 2;
  };

  let maxSq = 0;
  let idx = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = sqDist(points[i], points[0], points[points.length - 1]);
    if (d > maxSq) {
      maxSq = d;
      idx = i;
    }
  }

  if (maxSq > epsilon * epsilon) {
    const left = simplifyPolygon(points.slice(0, idx + 1), epsilon);
    const right = simplifyPolygon(points.slice(idx), epsilon);
    return [...left.slice(0, -1), ...right];
  }
  return [points[0], points[points.length - 1]];
}

export function convexHull(points: { x: number; y: number }[]): { x: number; y: number }[] {
  if (points.length < 3) return points;
  const sorted = [...points].sort((a, b) => a.x - b.x || a.y - b.y);
  const cross = (o: { x: number; y: number }, a: { x: number; y: number }, b: { x: number; y: number }) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  const lower: { x: number; y: number }[] = [];
  for (const p of sorted) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop();
    lower.push(p);
  }
  const upper: { x: number; y: number }[] = [];
  for (let i = sorted.length - 1; i >= 0; i--) {
    const p = sorted[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) upper.pop();
    upper.push(p);
  }
  upper.pop();
  lower.pop();
  return [...lower, ...upper];
}
