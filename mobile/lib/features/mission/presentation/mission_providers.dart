import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/providers.dart';
import '../data/hlb_local_cache.dart';
import '../data/local_mission_import_service.dart';
import '../data/mission_completion.dart';
import '../data/mission_intelligence_engine.dart';
import '../data/mission_local_first_service.dart';
import '../data/discovery_analytics.dart';
import '../data/hlb_local_state.dart';
import '../data/firebase_mission_repository.dart';
import '../data/hlb_export_template_layout.dart';
import '../models/mission_models.dart';
import '../utils/mission_navigation.dart';
import '../widgets/bearing_arrow.dart';
import 'eb_list_screen.dart';

class EbMissionQuery {
  const EbMissionQuery({required this.ebId, required this.projectId});

  final String ebId;
  final String projectId;

  @override
  bool operator ==(Object other) =>
      other is EbMissionQuery && other.ebId == ebId && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(ebId, projectId);
}

final appLaunchLocationProvider = FutureProvider<Position?>((ref) async {
  final allowed = await ensureMissionLocationPermission();
  if (!allowed) return null;
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  } catch (_) {
    return null;
  }
});

final hlbLocalCacheProvider = Provider<HlbLocalCache>((ref) => HlbLocalCache());

final missionLocalFirstProvider = Provider<MissionLocalFirstService>((ref) {
  return MissionLocalFirstService(
    cache: ref.watch(hlbLocalCacheProvider),
    firebase: ref.watch(firebaseMissionRepositoryProvider),
  );
});

final localMissionImportProvider = Provider<LocalMissionImportService>((ref) {
  return LocalMissionImportService(cache: ref.watch(hlbLocalCacheProvider));
});

Future<void> _ensureEbInitialized(Ref ref, EbMissionQuery query) async {
  final local = ref.read(missionLocalFirstProvider);
  final cached = await ref.read(hlbLocalCacheProvider).get(query.ebId);
  if (cached != null) {
    local.syncInBackground(query.ebId);
    return;
  }
  EnumerationBlock? eb;
  try {
    final ebs = await ref.read(firebaseMissionRepositoryProvider).listEbs(query.projectId);
    for (final candidate in ebs) {
      if (candidate.id == query.ebId) {
        eb = candidate;
        break;
      }
    }
  } catch (_) {}
  await local.initEb(
    ebId: query.ebId,
    ebCode: eb?.ebCode ?? 'EB',
    projectId: query.projectId,
  );
}

final discoveryStatusProvider = FutureProvider.family<DiscoveryStatus, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  return ref.watch(missionLocalFirstProvider).getDiscovery(query.ebId);
});

final missionCompletionProvider = FutureProvider.family<MissionCompletionIndex, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  final state = await ref.read(missionLocalFirstProvider).getRawState(query.ebId);
  if (state == null) {
    return MissionCompletionIndex(
      coveragePercent: 0,
      observationTargetsCompletedPercent: 0,
      roadsWalkedPercent: 0,
      boundaryVerifiedPercent: 0,
      ignoredTargets: 0,
      openGaps: 0,
      overallPercent: 0,
      canSubmit: false,
    );
  }
  return MissionCompletionIndex.compute(state);
});

final missionIntelligenceProvider = FutureProvider.family<MissionIntelligenceSummary?, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  final state = await ref.read(missionLocalFirstProvider).getRawState(query.ebId);
  if (state == null) return null;
  return MissionIntelligenceEngine.summary(state);
});

final draftMapProvider = FutureProvider.family<DraftHlbMap, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  return ref.watch(missionLocalFirstProvider).getDraftMap(query.ebId);
});

final hlbExportTemplateProvider = FutureProvider.family<HlbExportTemplateLayout, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  final state = await ref.read(missionLocalFirstProvider).getRawState(query.ebId);
  return resolveHlbExportTemplate(state?.layoutGeoref, query.ebId);
});

class CoverageGapsQuery {
  const CoverageGapsQuery({
    required this.ebId,
    required this.projectId,
    this.latitude,
    this.longitude,
  });

  final String ebId;
  final String projectId;
  final double? latitude;
  final double? longitude;

  EbMissionQuery get mission => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  bool operator ==(Object other) =>
      other is CoverageGapsQuery &&
      other.ebId == ebId &&
      other.projectId == projectId &&
      other.latitude?.toStringAsFixed(4) == latitude?.toStringAsFixed(4) &&
      other.longitude?.toStringAsFixed(4) == longitude?.toStringAsFixed(4);

  @override
  int get hashCode => Object.hash(ebId, projectId, latitude?.toStringAsFixed(4), longitude?.toStringAsFixed(4));
}

final coverageGapsProvider = FutureProvider.family<CoverageGapsResponse, CoverageGapsQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query.mission);
  return ref.watch(missionLocalFirstProvider).getCoverageGaps(
        query.ebId,
        latitude: query.latitude,
        longitude: query.longitude,
      );
});

class HlbAnalytics {
  const HlbAnalytics({
    required this.heatmap,
    required this.streets,
    required this.replay,
    required this.ignoredCount,
    required this.ignoredSuggestions,
  });

  final List<HeatmapCell> heatmap;
  final List<StreetSegment> streets;
  final List<DiscoveryReplayEvent> replay;
  final int ignoredCount;
  final List<LocalIgnoredSuggestion> ignoredSuggestions;

  static const empty = HlbAnalytics(
    heatmap: [],
    streets: [],
    replay: [],
    ignoredCount: 0,
    ignoredSuggestions: [],
  );
}

final hlbAnalyticsProvider = FutureProvider.family<HlbAnalytics, EbMissionQuery>((ref, query) async {
  await _ensureEbInitialized(ref, query);
  final state = await ref.read(missionLocalFirstProvider).getRawState(query.ebId);
  if (state == null) return HlbAnalytics.empty;
  return HlbAnalytics(
    heatmap: DiscoveryAnalytics.computeHeatmap(state),
    streets: DiscoveryAnalytics.computeStreets(state),
    replay: DiscoveryAnalytics.buildReplay(state),
    ignoredCount: DiscoveryAnalytics.ignoredCount(state),
    ignoredSuggestions: state.ignoredSuggestions,
  );
});

const kDefaultEbCode = 'HLB';

Future<EnumerationBlock> ensureEnumeratorEb(WidgetRef ref, String projectId) async {
  final cloud = ref.read(firebaseMissionRepositoryProvider);
  final pid = projectId.isNotEmpty ? projectId : FirebaseMissionRepository.defaultProjectId;
  final existing = await cloud.listEbs(pid);
  if (existing.isNotEmpty) {
    final eb = existing.first;
    await ref.read(missionLocalFirstProvider).initEb(
          ebId: eb.id,
          ebCode: eb.ebCode,
          projectId: pid,
        );
    return eb;
  }
  final eb = await cloud.createEb(projectId: pid, ebCode: kDefaultEbCode);
  await ref.read(missionLocalFirstProvider).initEb(
        ebId: eb.id,
        ebCode: eb.ebCode,
        projectId: pid,
      );
  ref.invalidate(ebListProvider(pid));
  return eb;
}

Future<void> applyPdfEbCode(WidgetRef ref, {required String projectId, required String ebId, required String ebCode}) async {
  final code = ebCode.trim();
  if (code.isEmpty) return;
  await ref.read(firebaseMissionRepositoryProvider).updateEbCode(projectId, ebId, code);
  await ref.read(missionLocalFirstProvider).updateEbCode(ebId, code);
  ref.invalidate(ebListProvider(projectId));
  ref.invalidate(activeMissionProvider);
}

final activeMissionProvider = FutureProvider<ActiveMission?>((ref) async {
  final projects = await ref.watch(projectsProvider.future);

  for (final project in projects) {
    final ebs = await ref.watch(ebListProvider(project.id).future);
    for (final eb in ebs) {
      if (eb.status == 'draft') {
        return ActiveMission(projectId: project.id, ebId: eb.id, ebCode: eb.ebCode, phase: 'mapping');
      }
      if (eb.status == 'published' && !eb.isComplete) {
        final phase = eb.totalBuildings == 0 || eb.progressPercent == 0 ? 'mapping' : 'listing';
        if (phase == 'mapping') {
          return ActiveMission(projectId: project.id, ebId: eb.id, ebCode: eb.ebCode, phase: 'mapping');
        }
        return ActiveMission(projectId: project.id, ebId: eb.id, ebCode: eb.ebCode, phase: 'listing');
      }
    }
  }
  return null;
});
