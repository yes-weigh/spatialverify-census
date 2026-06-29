import 'hlb_geo_engine.dart';
import 'hlb_local_state.dart';

/// Merges officer-map hypotheses with live discovery — predicted world → human verification.
class MissionIntelligenceEngine {
  static Map<String, dynamic>? intelligenceMap(HlbLocalState state) {
    if (state.missionIntelligence != null) return state.missionIntelligence;
    final lg = state.layoutGeoref;
    if (lg?['missionIntelligence'] != null) {
      return Map<String, dynamic>.from(lg!['missionIntelligence'] as Map);
    }
    return null;
  }

  static MissionIntelligenceSummary? summary(HlbLocalState state) {
    final mi = intelligenceMap(state);
    if (mi == null) return null;
    final s = mi['summary'] as Map<String, dynamic>?;
    final alignment = mi['alignment'] as Map<String, dynamic>?;
    if (s == null) return null;
    return MissionIntelligenceSummary(
      observationTargets: s['observationTargets'] as int? ?? s['estimatedStructures'] as int? ?? 0,
      roadSegments: s['roadSegments'] as int? ?? 0,
      possibleLandmarks: s['possibleLandmarks'] as int? ?? 0,
      canalCrossings: s['canalCrossings'] as int? ?? 0,
      alignmentQualityPercent: alignment?['qualityPercent'] as int? ?? 0,
    );
  }

  static List<Map<String, dynamic>> structureHypotheses(HlbLocalState state) {
    final mi = intelligenceMap(state);
    if (mi != null) {
      final h = mi['hypotheses'] as Map<String, dynamic>?;
      final list = h?['observationTargets'] as List<dynamic>? ??
          h?['structures'] as List<dynamic>?;
      if (list != null) return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final ps = state.layoutGeoref?['potentialStructures'] as List<dynamic>?;
    return ps?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  static int confirmedHypothesisCount(HlbLocalState state) {
    final hypotheses = structureHypotheses(state);
    final confirmed = state.buildings.length;
    var matched = 0;
    for (final h in hypotheses) {
      final lat = (h['lat'] as num?)?.toDouble();
      final lng = (h['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final near = state.buildings.any(
        (b) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, lat, lng) < 35,
      );
      if (near) matched++;
    }
    return matched.clamp(0, confirmed);
  }

  static int unvalidatedHypothesisCount(HlbLocalState state) {
    final hypotheses = structureHypotheses(state);
    var count = 0;
    for (final h in hypotheses) {
      final lat = (h['lat'] as num?)?.toDouble();
      final lng = (h['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final near = state.buildings.any(
        (b) => HlbGeoEngine.haversineMeters(b.latitude, b.longitude, lat, lng) < 35,
      );
      final ignored = state.ignoredSuggestions.any(
        (s) => s.id == (h['id'] as String? ?? '') ||
            (s.latitude != null &&
                s.longitude != null &&
                HlbGeoEngine.haversineMeters(s.latitude!, s.longitude!, lat, lng) < 20),
      );
      if (!near && !ignored) count++;
    }
    return count;
  }
}

class MissionIntelligenceSummary {
  const MissionIntelligenceSummary({
    required this.observationTargets,
    required this.roadSegments,
    required this.possibleLandmarks,
    required this.canalCrossings,
    required this.alignmentQualityPercent,
  });

  final int observationTargets;
  final int roadSegments;
  final int possibleLandmarks;
  final int canalCrossings;
  final int alignmentQualityPercent;

  int get estimatedStructures => observationTargets;

  bool get hasData => observationTargets > 0 || roadSegments > 0;
}
