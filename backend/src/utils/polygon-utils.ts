import type { GeoJSONPolygon, HlbStartPoint } from '../types/hlb-boundary.js';

/** North-West most vertex: max latitude, then min longitude among ties. */
export function computeNorthWestStartPoint(ring: number[][]): HlbStartPoint {
  if (ring.length === 0) return { lat: 0, lng: 0 };
  let best = ring[0];
  for (const [lng, lat] of ring) {
    if (lat > best[1] || (lat === best[1] && lng < best[0])) {
      best = [lng, lat];
    }
  }
  return { lat: best[1], lng: best[0] };
}

export function exteriorRing(polygon: GeoJSONPolygon): number[][] {
  return polygon.coordinates[0] ?? [];
}

export function ringToLatLng(ring: number[][]): Array<{ lat: number; lng: number }> {
  return ring.map(([lng, lat]) => ({ lat, lng }));
}

/** Ray-casting point-in-polygon (GeoJSON exterior ring, lng/lat order). */
export function pointInPolygon(lat: number, lng: number, polygon: GeoJSONPolygon): boolean {
  const ring = exteriorRing(polygon);
  if (ring.length < 3) return false;
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0];
    const yi = ring[i][1];
    const xj = ring[j][0];
    const yj = ring[j][1];
    const intersect = yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi + 0.0) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

export function parseGeoJsonPolygon(input: unknown): GeoJSONPolygon {
  const obj = input as GeoJSONPolygon;
  if (obj?.type !== 'Polygon' || !Array.isArray(obj.coordinates)) {
    throw new Error('Invalid GeoJSON Polygon');
  }
  return obj;
}
