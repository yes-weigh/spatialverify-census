import type { MissionBuilding } from '../types/mission.js';
import { haversineMeters } from './geo.js';

export type NextBuildingStrategy = 'nearest' | 'route';

export function isPendingBuilding(b: MissionBuilding): boolean {
  return b.status !== 'completed';
}

/** Route-following next building (original behaviour). */
export function findRouteNextBuilding(
  buildings: MissionBuilding[],
  routeIds: string[]
): MissionBuilding | null {
  const byId = new Map(buildings.map((b) => [b.id, b]));

  if (routeIds?.length) {
    for (const id of routeIds) {
      const b = byId.get(id);
      if (b && isPendingBuilding(b)) return b;
    }
  }

  return (
    buildings.find((b) => b.status === 'not_visited' || b.status === 'visited') ?? null
  );
}

/**
 * Smart next stop: nearest pending building with a GPS pin when enumerator position known.
 * Falls back to route order when GPS unavailable.
 */
export function findSmartNextBuilding(
  buildings: MissionBuilding[],
  routeIds: string[],
  lat?: number,
  lng?: number
): { building: MissionBuilding | null; strategy: NextBuildingStrategy } {
  const pending = buildings.filter(isPendingBuilding);
  if (pending.length === 0) return { building: null, strategy: 'route' };

  if (lat != null && lng != null) {
    const withGps = pending.filter(
      (b) => b.latitude != null && b.longitude != null
    );
    if (withGps.length > 0) {
      let nearest = withGps[0];
      let minDist = haversineMeters(lat, lng, nearest.latitude!, nearest.longitude!);
      for (const b of withGps.slice(1)) {
        const d = haversineMeters(lat, lng, b.latitude!, b.longitude!);
        if (d < minDist) {
          minDist = d;
          nearest = b;
        }
      }
      return { building: nearest, strategy: 'nearest' };
    }
  }

  return { building: findRouteNextBuilding(buildings, routeIds), strategy: 'route' };
}

/** Estimate minutes to visit all remaining buildings from current position. */
export function estimateRemainingMinutes(
  remaining: MissionBuilding[],
  lat: number | undefined,
  lng: number | undefined,
  avgTravelMinutes: number,
  avgSurveyMinutes: number
): number {
  if (remaining.length === 0) return 0;

  let travelMinutes = 0;
  let cursorLat = lat;
  let cursorLng = lng;

  const sorted = [...remaining].sort((a, b) => {
    if (cursorLat == null || cursorLng == null) {
      return (a.route_sequence ?? a.building_number) - (b.route_sequence ?? b.building_number);
    }
    const da =
      a.latitude != null && a.longitude != null
        ? haversineMeters(cursorLat, cursorLng, a.latitude, a.longitude)
        : Number.MAX_SAFE_INTEGER;
    const db =
      b.latitude != null && b.longitude != null
        ? haversineMeters(cursorLat, cursorLng, b.latitude, b.longitude)
        : Number.MAX_SAFE_INTEGER;
    return da - db;
  });

  for (const b of sorted) {
    if (
      cursorLat != null &&
      cursorLng != null &&
      b.latitude != null &&
      b.longitude != null
    ) {
      const meters = haversineMeters(cursorLat, cursorLng, b.latitude, b.longitude);
      travelMinutes += Math.max(1, Math.round(meters / (4000 / 60)));
      cursorLat = b.latitude;
      cursorLng = b.longitude;
    } else {
      travelMinutes += avgTravelMinutes;
    }
    travelMinutes += avgSurveyMinutes;
  }

  return Math.max(1, Math.round(travelMinutes));
}
