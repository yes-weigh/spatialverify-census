import type { ImageBounds } from '../types/layout-georef.js';

const M_PER_DEG_LAT = 111320;

export function imageUvToLatLng(u: number, v: number, bounds: ImageBounds): { lat: number; lng: number } {
  const lat = bounds.south + (1 - v) * (bounds.north - bounds.south);
  const lng = bounds.west + u * (bounds.east - bounds.west);
  return { lat, lng };
}

export function boundsFromCenter(
  centerLat: number,
  centerLng: number,
  widthMeters: number,
  heightMeters: number
): ImageBounds {
  const latSpan = heightMeters / M_PER_DEG_LAT;
  const lngSpan = widthMeters / (M_PER_DEG_LAT * Math.cos((centerLat * Math.PI) / 180));
  return {
    north: centerLat + latSpan / 2,
    south: centerLat - latSpan / 2,
    east: centerLng + lngSpan / 2,
    west: centerLng - lngSpan / 2,
    rotation: 0,
  };
}

export function shiftBounds(bounds: ImageBounds, dNorthM: number, dEastM: number, centerLat: number): ImageBounds {
  const dLat = dNorthM / M_PER_DEG_LAT;
  const dLng = dEastM / (M_PER_DEG_LAT * Math.cos((centerLat * Math.PI) / 180));
  return {
    north: bounds.north + dLat,
    south: bounds.south + dLat,
    east: bounds.east + dLng,
    west: bounds.west + dLng,
    rotation: bounds.rotation ?? 0,
  };
}

export function scaleBounds(bounds: ImageBounds, factor: number, centerLat: number, centerLng: number): ImageBounds {
  const halfLat = ((bounds.north - bounds.south) / 2) * factor;
  const halfLng = ((bounds.east - bounds.west) / 2) * factor;
  return {
    north: centerLat + halfLat,
    south: centerLat - halfLat,
    east: centerLng + halfLng,
    west: centerLng - halfLng,
    rotation: bounds.rotation ?? 0,
  };
}

export function polygonAreaSqMeters(ring: Array<{ lat: number; lng: number }>): number {
  if (ring.length < 3) return 0;
  const center = ring.reduce((a, p) => ({ lat: a.lat + p.lat, lng: a.lng + p.lng }), { lat: 0, lng: 0 });
  center.lat /= ring.length;
  center.lng /= ring.length;
  const mPerDegLng = M_PER_DEG_LAT * Math.cos((center.lat * Math.PI) / 180);
  let area = 0;
  for (let i = 0; i < ring.length; i++) {
    const j = (i + 1) % ring.length;
    const xi = (ring[i].lng - center.lng) * mPerDegLng;
    const yi = (ring[i].lat - center.lat) * M_PER_DEG_LAT;
    const xj = (ring[j].lng - center.lng) * mPerDegLng;
    const yj = (ring[j].lat - center.lat) * M_PER_DEG_LAT;
    area += xi * yj - xj * yi;
  }
  return Math.abs(area) / 2;
}

export function alignmentQualityFromBounds(bounds: ImageBounds): 'excellent' | 'good' | 'needs_review' {
  const span = Math.max(bounds.north - bounds.south, bounds.east - bounds.west);
  if (span > 0.00005 && span < 0.02) return 'excellent';
  if (span > 0.00002 && span < 0.05) return 'good';
  return 'needs_review';
}
