import { describe, it, expect } from 'vitest';
import { encodeGeohash, geohashSearchCells } from '../utils/geohash.js';

describe('geohash utility', () => {
  it('encodeGeohash produces stable precision-7 buckets', () => {
    const hash = encodeGeohash(10.14520, 76.32110, 7);
    expect(hash).toHaveLength(7);
    expect(hash).toBe(encodeGeohash(10.14520, 76.32110, 7));
  });

  it('geohashSearchCells returns center + neighbors', () => {
    const cells = geohashSearchCells(10.14520, 76.32110, 7);
    expect(cells.length).toBeGreaterThanOrEqual(1);
    expect(cells.length).toBeLessThanOrEqual(9);
    expect(cells).toContain(encodeGeohash(10.14520, 76.32110, 7));
  });

  it('nearby coordinates share geohash bucket at precision 7', () => {
    const a = encodeGeohash(10.14520, 76.32110, 7);
    const b = encodeGeohash(10.14525, 76.32115, 7);
    expect(a).toBe(b);
  });
});
