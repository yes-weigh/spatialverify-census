import { haversineMeters } from './geo.js';

export interface GpsPoint {
  id: string;
  latitude: number;
  longitude: number;
  buildingNumber?: number;
}

/** NW → SE serpentine ordering per Census HLB training (north-up, row-wise). */
export function serpentineOrder(points: GpsPoint[], rowWidthMeters = 40): GpsPoint[] {
  if (points.length <= 1) return [...points];

  const lats = points.map((p) => p.latitude);
  const lngs = points.map((p) => p.longitude);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);

  const latSpan = Math.max(maxLat - minLat, 0.00001);
  const rows = Math.max(1, Math.ceil((latSpan * 111320) / rowWidthMeters));

  const withRow = points.map((p) => ({
    ...p,
    row: Math.min(rows - 1, Math.floor(((maxLat - p.latitude) / latSpan) * rows)),
  }));

  withRow.sort((a, b) => {
    if (a.row !== b.row) return a.row - b.row;
    const oddRow = a.row % 2 === 0;
    return oddRow ? a.longitude - b.longitude : b.longitude - a.longitude;
  });

  return withRow;
}

export function suggestSerpentineNumber(lat: number, lng: number, existing: GpsPoint[]): number {
  if (existing.length === 0) return 1;
  const combined = serpentineOrder([...existing, { id: 'new', latitude: lat, longitude: lng }]);
  const idx = combined.findIndex((p) => p.id === 'new');
  return idx >= 0 ? idx + 1 : existing.length + 1;
}

export interface NumberingIssue {
  buildingId: string;
  buildingNumber: number;
  expectedNumber: number;
}

export function detectNumberingIssues(buildings: GpsPoint[]): NumberingIssue[] {
  const ordered = serpentineOrder(buildings.filter((b) => b.latitude != null && b.longitude != null));
  const issues: NumberingIssue[] = [];
  ordered.forEach((b, i) => {
    const expected = i + 1;
    if (b.buildingNumber != null && b.buildingNumber !== expected) {
      issues.push({ buildingId: b.id, buildingNumber: b.buildingNumber, expectedNumber: expected });
    }
  });
  return issues;
}

export function projectToMapCoords(
  lat: number,
  lng: number,
  bounds: { minLat: number; maxLat: number; minLng: number; maxLng: number }
): { x: number; y: number } {
  const latSpan = Math.max(bounds.maxLat - bounds.minLat, 0.0001);
  const lngSpan = Math.max(bounds.maxLng - bounds.minLng, 0.0001);
  return {
    x: (lng - bounds.minLng) / lngSpan,
    y: (bounds.maxLat - lat) / latSpan,
  };
}

export function computeBounds(points: Array<{ latitude: number; longitude: number }>) {
  if (points.length === 0) return { minLat: 0, maxLat: 1, minLng: 0, maxLng: 1 };
  return {
    minLat: Math.min(...points.map((p) => p.latitude)),
    maxLat: Math.max(...points.map((p) => p.latitude)),
    minLng: Math.min(...points.map((p) => p.longitude)),
    maxLng: Math.max(...points.map((p) => p.longitude)),
  };
}

export function estimatePathCoveragePercent(
  breadcrumbs: Array<{ latitude: number; longitude: number }>,
  bounds: { minLat: number; maxLat: number; minLng: number; maxLng: number },
  gridSize = 8
): number {
  if (breadcrumbs.length === 0) return 0;
  const visited = new Set<string>();
  for (const b of breadcrumbs) {
    const { x, y } = projectToMapCoords(b.latitude, b.longitude, bounds);
    if (x >= 0 && x <= 1 && y >= 0 && y <= 1) {
      visited.add(`${Math.min(gridSize - 1, Math.floor(x * gridSize))},${Math.min(gridSize - 1, Math.floor(y * gridSize))}`);
    }
  }
  return Math.round((visited.size / (gridSize * gridSize)) * 100);
}

export function findUnvisitedGridCells(
  breadcrumbs: Array<{ latitude: number; longitude: number }>,
  bounds: { minLat: number; maxLat: number; minLng: number; maxLng: number },
  gridSize = 8
): Array<{ lat: number; lng: number; cellX: number; cellY: number }> {
  if (breadcrumbs.length === 0) return [];

  const visited = new Set<string>();
  for (const b of breadcrumbs) {
    const { x, y } = projectToMapCoords(b.latitude, b.longitude, bounds);
    if (x >= 0 && x <= 1 && y >= 0 && y <= 1) {
      visited.add(`${Math.min(gridSize - 1, Math.floor(x * gridSize))},${Math.min(gridSize - 1, Math.floor(y * gridSize))}`);
    }
  }

  const latSpan = Math.max(bounds.maxLat - bounds.minLat, 0.0001);
  const lngSpan = Math.max(bounds.maxLng - bounds.minLng, 0.0001);
  const cells: Array<{ lat: number; lng: number; cellX: number; cellY: number }> = [];

  for (let cx = 0; cx < gridSize; cx++) {
    for (let cy = 0; cy < gridSize; cy++) {
      if (visited.has(`${cx},${cy}`)) continue;
      const x = (cx + 0.5) / gridSize;
      const y = (cy + 0.5) / gridSize;
      cells.push({
        lat: bounds.maxLat - y * latSpan,
        lng: bounds.minLng + x * lngSpan,
        cellX: cx,
        cellY: cy,
      });
    }
  }

  return cells.slice(0, 12);
}

export function findUnrecordedClusters(
  breadcrumbs: Array<{ latitude: number; longitude: number }>,
  buildings: GpsPoint[],
  minDistanceMeters = 80
): Array<{ lat: number; lng: number; breadcrumbCount: number }> {
  if (buildings.length === 0 || breadcrumbs.length < 5) return [];
  const clusters: Array<{ lat: number; lng: number; breadcrumbCount: number }> = [];
  const window = 5;
  for (let i = 0; i < breadcrumbs.length; i += window) {
    const slice = breadcrumbs.slice(i, i + window);
    const lat = slice.reduce((s, p) => s + p.latitude, 0) / slice.length;
    const lng = slice.reduce((s, p) => s + p.longitude, 0) / slice.length;
    const nearBuilding = buildings.some(
      (b) => haversineMeters(lat, lng, b.latitude, b.longitude) < minDistanceMeters
    );
    if (!nearBuilding) clusters.push({ lat, lng, breadcrumbCount: slice.length });
  }
  return clusters.slice(0, 5);
}

export function formatCn(n: number): string {
  return `CN-${String(n).padStart(3, '0')}`;
}
