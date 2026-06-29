import 'hlb_geo_engine.dart';
import 'hlb_local_state.dart';
import 'hlb_state_computer.dart';
import 'mission_intelligence_engine.dart';

/// Answers: "Can I confidently submit this HLB?"
class MissionCompletionIndex {
  const MissionCompletionIndex({
    required this.coveragePercent,
    required this.observationTargetsCompletedPercent,
    required this.roadsWalkedPercent,
    required this.boundaryVerifiedPercent,
    required this.ignoredTargets,
    required this.openGaps,
    required this.overallPercent,
    required this.canSubmit,
  });

  final int coveragePercent;
  final int observationTargetsCompletedPercent;
  final int roadsWalkedPercent;
  final int boundaryVerifiedPercent;
  final int ignoredTargets;
  final int openGaps;
  final int overallPercent;
  final bool canSubmit;

  static MissionCompletionIndex compute(HlbLocalState state) {
    final intel = MissionIntelligenceEngine.summary(state);
    final totalTargets = intel?.estimatedStructures ??
        MissionIntelligenceEngine.structureHypotheses(state).length;
    final validated = MissionIntelligenceEngine.confirmedHypothesisCount(state);
    final targetPct = totalTargets > 0 ? ((validated / totalTargets) * 100).round().clamp(0, 100) : 100;

    final bc = state.breadcrumbs;
    final pathM = bc.length >= 2
        ? HlbGeoEngine.pathWalkedMeters(bc.map((b) => GpsCoord(b.latitude, b.longitude)).toList())
        : 0.0;
    final roadsPct = pathM > 200 ? 100 : pathM > 50 ? 70 : pathM > 0 ? 40 : 0;

    final boundaryPct = state.hasOfficialBoundary ? 100 : (state.boundaryVertices.length >= 3 ? 80 : 0);

    final ring = state.officialBoundaryRing;
    var coveragePct = 0;
    if (ring.isNotEmpty && bc.isNotEmpty) {
      final inside = bc.where((b) => HlbGeoEngine.pointInPolygon(b.latitude, b.longitude, ring)).length;
      coveragePct = ((inside / bc.length) * 100).round().clamp(0, 100);
    } else if (bc.length > 10) {
      coveragePct = 60;
    }

    final openGaps = HlbStateComputer.detectGaps(state).where((g) => !g.isResolved).length;
    final ignored = state.ignoredSuggestions.length;

    final overall = (
      coveragePct * 0.3 +
      targetPct * 0.25 +
      roadsPct * 0.2 +
      boundaryPct * 0.15 +
      (openGaps == 0 ? 100 : (100 - openGaps * 15).clamp(0, 100)) * 0.1
    ).round().clamp(0, 100);

    final canSubmit = state.hasOfficialBoundary &&
        state.buildings.isNotEmpty &&
        openGaps == 0 &&
        overall >= 75;

    return MissionCompletionIndex(
      coveragePercent: coveragePct,
      observationTargetsCompletedPercent: targetPct,
      roadsWalkedPercent: roadsPct,
      boundaryVerifiedPercent: boundaryPct,
      ignoredTargets: ignored,
      openGaps: openGaps,
      overallPercent: overall,
      canSubmit: canSubmit,
    );
  }
}

class SpatialConfidenceScores {
  const SpatialConfidenceScores({
    required this.boundary,
    required this.structures,
    required this.roads,
    required this.landmarks,
    required this.overall,
  });

  final int boundary;
  final int structures;
  final int roads;
  final int landmarks;
  final int overall;

  factory SpatialConfidenceScores.fromIntelligence(Map<String, dynamic> intel) {
    final c = intel['confidence'] as Map<String, dynamic>? ?? {};
    int pct(num? v) => (((v ?? 0).toDouble()) * 100).round().clamp(0, 100);
    return SpatialConfidenceScores(
      boundary: pct(c['boundary'] as num?),
      structures: pct(c['structures'] as num?),
      roads: pct(c['roads'] as num?),
      landmarks: pct(c['landmarks'] as num?),
      overall: pct(c['overall'] as num?),
    );
  }
}
