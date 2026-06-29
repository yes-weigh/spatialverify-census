/**
 * Minimal geohash encoder for coarse spatial pre-filtering.
 * Precision 7 ≈ 153m cells — expanded with neighbor offsets for 50m search.
 */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function encodeGeohash(latitude: number, longitude: number, precision = 7): string {
  let idx = 0;
  let bit = 0;
  let evenBit = true;
  let geohash = '';

  let latMin = -90;
  let latMax = 90;
  let lonMin = -180;
  let lonMax = 180;

  while (geohash.length < precision) {
    if (evenBit) {
      const mid = (lonMin + lonMax) / 2;
      if (longitude >= mid) {
        idx = idx * 2 + 1;
        lonMin = mid;
      } else {
        idx = idx * 2;
        lonMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        idx = idx * 2 + 1;
        latMin = mid;
      } else {
        idx = idx * 2;
        latMax = mid;
      }
    }

    evenBit = !evenBit;

    if (++bit === 5) {
      geohash += BASE32[idx];
      bit = 0;
      idx = 0;
    }
  }

  return geohash;
}

function decodeBounds(geohash: string): {
  latMin: number;
  latMax: number;
  lonMin: number;
  lonMax: number;
} {
  let evenBit = true;
  let latMin = -90;
  let latMax = 90;
  let lonMin = -180;
  let lonMax = 180;

  for (const char of geohash) {
    const idx = BASE32.indexOf(char);
    for (let bit = 4; bit >= 0; bit--) {
      const mask = 1 << bit;
      if (evenBit) {
        const mid = (lonMin + lonMax) / 2;
        if (idx & mask) lonMin = mid;
        else lonMax = mid;
      } else {
        const mid = (latMin + latMax) / 2;
        if (idx & mask) latMin = mid;
        else latMax = mid;
      }
      evenBit = !evenBit;
    }
  }

  return { latMin, latMax, lonMin, lonMax };
}

/** Return center cell + 8 neighbors for bounded geo pre-filter. */
export function geohashSearchCells(latitude: number, longitude: number, precision = 7): string[] {
  const center = encodeGeohash(latitude, longitude, precision);
  const cells = new Set<string>([center]);

  const { latMin, latMax, lonMin, lonMax } = decodeBounds(center);
  const latStep = latMax - latMin;
  const lonStep = lonMax - lonMin;

  const offsets = [
    [0, 0], [0, 1], [0, -1], [1, 0], [-1, 0],
    [1, 1], [1, -1], [-1, 1], [-1, -1],
  ];

  for (const [dLat, dLon] of offsets) {
    const lat = latitude + dLat * latStep;
    const lon = longitude + dLon * lonStep;
    if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
      cells.add(encodeGeohash(lat, lon, precision));
    }
  }

  return [...cells];
}
