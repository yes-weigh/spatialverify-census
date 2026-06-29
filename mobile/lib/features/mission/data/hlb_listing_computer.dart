import '../models/mission_models.dart';
import 'hlb_geo_engine.dart';
import 'hlb_local_state.dart';

/// House-listing dashboard, route, and coverage — derived from on-device HLB state.
class HlbListingComputer {
  static List<MissionBuilding> toMissionBuildings(HlbLocalState state) {
    final gpsBuildings = state.buildings
        .map((b) => GpsBuilding(b.localId, b.latitude, b.longitude, b.buildingNumber))
        .toList();
    final ordered = HlbGeoEngine.serpentineOrder(gpsBuildings);
    final sequenceById = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i + 1};

    return state.buildings.map((b) {
      return MissionBuilding(
        id: b.localId,
        ebId: state.ebId,
        buildingNumber: b.buildingNumber,
        censusHouseCount: b.censusHouseCount,
        buildingType: b.buildingType,
        mapX: b.mapX,
        mapY: b.mapY,
        status: b.status,
        notes: b.notes,
        routeSequence: sequenceById[b.localId],
        latitude: b.latitude,
        longitude: b.longitude,
      );
    }).toList();
  }

  static List<String> routeBuildingIds(HlbLocalState state) {
    final buildings = toMissionBuildings(state);
    buildings.sort((a, b) => (a.routeSequence ?? a.buildingNumber).compareTo(b.routeSequence ?? b.buildingNumber));
    return buildings.map((b) => b.id).toList();
  }

  static MissionDashboard dashboard(HlbLocalState state, {double? lat, double? lng}) {
    final buildings = toMissionBuildings(state);
    final completed = buildings.where((b) => b.status == 'completed').length;
    final revisit = buildings.where((b) => b.status == 'revisit_required').length;
    final total = buildings.length;
    final remaining = buildings.where((b) => b.status != 'completed').length;
    final progress = total == 0 ? 0.0 : (completed / total) * 100;

    final routeIds = routeBuildingIds(state);
    final next = _findSmartNext(buildings, routeIds, lat, lng);

    return MissionDashboard(
      ebId: state.ebId,
      ebCode: state.ebCode,
      totalBuildings: total,
      completedBuildings: completed,
      remainingBuildings: remaining,
      progressPercent: progress,
      revisitRequired: revisit,
      nextBuilding: next.building,
      nextBuildingStrategy: next.strategy,
      layoutImageUrl: state.layoutGeoref?['layoutImagePath'] as String?,
    );
  }

  static DayReview dayReview(HlbLocalState state, {double? lat, double? lng}) {
    final buildings = toMissionBuildings(state);
    final remaining = buildings.where((b) => b.status != 'completed').toList();
    final completed = buildings.length - remaining.length;
    final progress = buildings.isEmpty ? 0.0 : (completed / buildings.length) * 100;
    final remainingNumbers = remaining.map((b) => b.buildingNumber).toList()..sort();

    const avgSurveyMinutes = 8;
    const avgTravelMinutes = 3;
    final estimated = _estimateRemainingMinutes(remaining, lat, lng, avgTravelMinutes, avgSurveyMinutes);

    return DayReview(
      ebId: state.ebId,
      ebCode: state.ebCode,
      progressPercent: progress,
      completedBuildings: completed,
      remainingBuildings: remaining.length,
      remainingBuildingNumbers: remainingNumbers,
      estimatedRemainingMinutes: estimated,
      avgMinutesPerBuilding: avgSurveyMinutes,
    );
  }

  static Map<String, dynamic> coverage(HlbLocalState state) {
    final buildings = toMissionBuildings(state);
    final total = buildings.length;
    final completed = buildings.where((b) => b.status == 'completed').length;
    final notVisited = buildings.where((b) => b.status == 'not_visited').map((b) => b.buildingNumber).toList();
    return {
      'coveragePercent': total == 0 ? 0.0 : (completed / total) * 100,
      'notVisitedBuildings': notVisited,
      'totalBuildings': total,
      'completedBuildings': completed,
    };
  }

  static List<MissionBuilding> route(HlbLocalState state) {
    final buildings = toMissionBuildings(state);
    final routeIds = routeBuildingIds(state);
    final byId = {for (final b in buildings) b.id: b};
    return routeIds.map((id) => byId[id]).whereType<MissionBuilding>().toList();
  }

  static ({MissionBuilding? building, String? strategy}) _findSmartNext(
    List<MissionBuilding> buildings,
    List<String> routeIds, [
    double? lat,
    double? lng,
  ]) {
    bool pending(MissionBuilding b) => b.status != 'completed';
    final open = buildings.where(pending).toList();
    if (open.isEmpty) return (building: null, strategy: null);

    if (lat != null && lng != null) {
      final withGps = open.where((b) => b.latitude != null && b.longitude != null).toList();
      if (withGps.isNotEmpty) {
        MissionBuilding nearest = withGps.first;
        var minDist = HlbGeoEngine.haversineMeters(lat, lng, nearest.latitude!, nearest.longitude!);
        for (final b in withGps.skip(1)) {
          final d = HlbGeoEngine.haversineMeters(lat, lng, b.latitude!, b.longitude!);
          if (d < minDist) {
            minDist = d;
            nearest = b;
          }
        }
        return (building: nearest, strategy: 'nearest');
      }
    }

    final byId = {for (final b in buildings) b.id: b};
    for (final id in routeIds) {
      final b = byId[id];
      if (b != null && pending(b)) return (building: b, strategy: 'route');
    }
    return (
      building: open.firstWhere((b) => b.status == 'not_visited' || b.status == 'visited', orElse: () => open.first),
      strategy: 'route',
    );
  }

  static int _estimateRemainingMinutes(
    List<MissionBuilding> remaining,
    double? lat,
    double? lng,
    int avgTravelMinutes,
    int avgSurveyMinutes,
  ) {
    if (remaining.isEmpty) return 0;

    var travelMinutes = 0;
    var cursorLat = lat;
    var cursorLng = lng;

    final sorted = [...remaining]..sort((a, b) {
        if (cursorLat == null || cursorLng == null) {
          return (a.routeSequence ?? a.buildingNumber).compareTo(b.routeSequence ?? b.buildingNumber);
        }
        final da = a.latitude != null && a.longitude != null
            ? HlbGeoEngine.haversineMeters(cursorLat, cursorLng, a.latitude!, a.longitude!)
            : double.maxFinite;
        final db = b.latitude != null && b.longitude != null
            ? HlbGeoEngine.haversineMeters(cursorLat, cursorLng, b.latitude!, b.longitude!)
            : double.maxFinite;
        return da.compareTo(db);
      });

    for (final b in sorted) {
      if (cursorLat != null && cursorLng != null && b.latitude != null && b.longitude != null) {
        final meters = HlbGeoEngine.haversineMeters(cursorLat, cursorLng, b.latitude!, b.longitude!);
        travelMinutes += (meters / (4000 / 60)).ceil().clamp(1, 999);
        cursorLat = b.latitude;
        cursorLng = b.longitude;
      } else {
        travelMinutes += avgTravelMinutes;
      }
      travelMinutes += avgSurveyMinutes;
    }

    return travelMinutes.clamp(1, 99999);
  }
}
