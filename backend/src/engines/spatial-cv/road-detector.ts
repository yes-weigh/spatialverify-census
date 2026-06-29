import { grayscale, interiorMask, loadRgbImage, toUv } from './boundary-detector.js';
import type { CvRoadSegment, UvPoint } from './types.js';

function isRoadGray(r: number, g: number, b: number): boolean {
  const gval = grayscale(r, g, b);
  return gval > 70 && gval < 195 && Math.abs(r - g) < 28 && Math.abs(g - b) < 28;
}

export async function detectRoadSegments(
  buffer: Buffer,
  boundaryUv: UvPoint[]
): Promise<{ segments: CvRoadSegment[]; confidence: number }> {
  const img = await loadRgbImage(buffer);
  const mask = boundaryUv.length >= 3 ? interiorMask(img, boundaryUv) : new Array(img.width * img.height).fill(true);

  const hLines: { y: number; x0: number; x1: number }[] = [];
  const vLines: { x: number; y0: number; y1: number }[] = [];

  for (let y = 0; y < img.height; y += 4) {
    let runStart = -1;
    for (let x = 0; x < img.width; x++) {
      const inside = mask[y * img.width + x];
      const i = (y * img.width + x) * 3;
      const road = inside && isRoadGray(img.data[i], img.data[i + 1], img.data[i + 2]);
      if (road && runStart < 0) runStart = x;
      if ((!road || x === img.width - 1) && runStart >= 0) {
        const end = road ? x : x - 1;
        if (end - runStart > img.width * 0.12) hLines.push({ y, x0: runStart, x1: end });
        runStart = -1;
      }
    }
  }

  for (let x = 0; x < img.width; x += 4) {
    let runStart = -1;
    for (let y = 0; y < img.height; y++) {
      const inside = mask[y * img.width + x];
      const i = (y * img.width + x) * 3;
      const road = inside && isRoadGray(img.data[i], img.data[i + 1], img.data[i + 2]);
      if (road && runStart < 0) runStart = y;
      if ((!road || y === img.height - 1) && runStart >= 0) {
        const end = road ? y : y - 1;
        if (end - runStart > img.height * 0.12) vLines.push({ x, y0: runStart, y1: end });
        runStart = -1;
      }
    }
  }

  const segments: CvRoadSegment[] = [];
  hLines.slice(0, 8).forEach((line, i) => {
    segments.push({
      id: `rd${i + 1}`,
      label: 'Road segment',
      points: [
        toUv(img, line.x0, line.y),
        toUv(img, (line.x0 + line.x1) / 2, line.y),
        toUv(img, line.x1, line.y),
      ],
      confidence: 0.75,
    });
  });
  vLines.slice(0, 8).forEach((line, i) => {
    segments.push({
      id: `rd${segments.length + 1}`,
      label: 'Road segment',
      points: [
        toUv(img, line.x, line.y0),
        toUv(img, line.x, (line.y0 + line.y1) / 2),
        toUv(img, line.x, line.y1),
      ],
      confidence: 0.72,
    });
  });

  const confidence = segments.length >= 3 ? 0.9 : segments.length > 0 ? 0.75 : 0.4;
  return { segments: segments.slice(0, 20), confidence };
}
