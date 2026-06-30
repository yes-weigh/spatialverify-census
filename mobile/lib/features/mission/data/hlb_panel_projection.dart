import 'package:latlong2/latlong.dart';

import '../models/layout_georef_models.dart';
import '../models/mission_models.dart';
import 'hlb_geo_engine.dart' hide MapPoint;
import 'hlb_local_state.dart';
import 'mission_map_session.dart';
import 'satellite_align_math.dart';

/// Overlay georef from saved mission intelligence / layoutGeoref.
ImageBounds? overlayBoundsFromState(HlbLocalState state) {
  final intelRaw = state.missionIntelligence ?? state.layoutGeoref?['missionIntelligence'];
  if (intelRaw is Map) {
    final intelMap = Map<String, dynamic>.from(intelRaw);
    final alignment = intelMap['alignment'] as Map<String, dynamic>?;
    if (alignment?['imageBounds'] != null) {
      return ImageBounds.fromJson(Map<String, dynamic>.from(alignment!['imageBounds'] as Map));
    }
  }
  final top = state.layoutGeoref?['imageBounds'];
  if (top is Map) {
    return ImageBounds.fromJson(Map<String, dynamic>.from(top));
  }
  return null;
}

List<({double x, double y})> uvRingFromState(HlbLocalState state) {
  Map<String, dynamic>? intelMap;
  final intelRaw = state.missionIntelligence ?? state.layoutGeoref?['missionIntelligence'];
  if (intelRaw is Map) {
    intelMap = Map<String, dynamic>.from(intelRaw);
  }
  return resolveMissionUvRing(
    intelligenceMap: intelMap,
    layoutGeoref: state.layoutGeoref,
  );
}

/// GPS → map-panel UV (0–1), matching the PDF overlay / satellite alignment.
MapPoint? gpsToPanelUv(HlbLocalState state, double lat, double lng) {
  final bounds = overlayBoundsFromState(state);
  if (bounds != null) {
    final uv = SatelliteAlignMath.imageUvFromLatLngRotated(LatLng(lat, lng), bounds);
    if (uv != null) return MapPoint(uv.u, uv.v);
  }
  return null;
}

MapPoint projectForDraftMap(HlbLocalState state, double lat, double lng) {
  final panel = gpsToPanelUv(state, lat, lng);
  if (panel != null) return panel;
  final p = HlbGeoEngine.projectToMap(lat, lng, _fallbackGeoBounds(state));
  return MapPoint(p.x, p.y);
}

MapBounds _fallbackGeoBounds(HlbLocalState state) {
  final ring = state.officialBoundaryRing;
  final all = <GpsCoord>[
    ...ring.map((p) => GpsCoord(p.lat, p.lng)),
    ...state.buildings.map((b) => GpsCoord(b.latitude, b.longitude)),
    ...state.breadcrumbs.map((b) => GpsCoord(b.latitude, b.longitude)),
  ];
  if (all.isEmpty) return const MapBounds(10, 10.001, 76, 76.001);
  return HlbGeoEngine.computeBounds(all);
}
