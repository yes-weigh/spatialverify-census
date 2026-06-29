import { describe, expect, it } from 'vitest';
import { runSpatialCvPipeline } from '../engines/spatial-cv/pipeline.js';
import sharp from 'sharp';

/** Synthetic officer map: red boundary rectangle on gray satellite-like background. */
async function syntheticOfficerMap(): Promise<Buffer> {
  const w = 400;
  const h = 300;
  const pixels = Buffer.alloc(w * h * 3, 120);
  for (let y = 20; y < h - 20; y++) {
    for (let x = 20; x < w - 20; x++) {
      const edge = x < 24 || x > w - 25 || y < 24 || y > h - 25;
      if (!edge) continue;
      const i = (y * w + x) * 3;
      pixels[i] = 220;
      pixels[i + 1] = 40;
      pixels[i + 2] = 40;
    }
  }
  return sharp(pixels, { raw: { width: w, height: h, channels: 3 } }).jpeg().toBuffer();
}

describe('spatial CV pipeline', () => {
  it('detects boundary and produces confidence scores offline', async () => {
    const buf = await syntheticOfficerMap();
    const result = await runSpatialCvPipeline(buf);
    expect(result.engine).toBe('spatial_cv');
    expect(result.boundaryPolygon.length).toBeGreaterThanOrEqual(3);
    expect(result.confidence.boundary).toBeGreaterThan(0.4);
    expect(result.confidence.overall).toBeGreaterThan(0);
  });
});
