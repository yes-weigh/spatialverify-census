import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/firebase_mission_repository.dart';
import '../models/mission_models.dart';
import 'mission_providers.dart';

/// Personal mission list — one enumerator, no supervisor workflow.
class MissionHubScreen extends ConsumerWidget {
  const MissionHubScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(ebListProvider(projectId));

    return Scaffold(
      appBar: AppBar(title: const Text('My HLB')),
      body: missionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (missions) {
          if (missions.isEmpty) {
            return _EmptyMissionState(onImportPdf: () => _importHloPdf(context, ref));
          }

          // One enumerator → one HLB; open it directly from the list.
          final mapping = missions.where((m) => m.status == 'draft').toList();
          final listing = missions.where((m) => m.status == 'published' && !m.isComplete).toList();
          final done = missions.where((m) => m.isComplete).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (mapping.isNotEmpty) ...[
                const Text('HLB Mapping', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final m in mapping)
                  _MissionCard(
                    mission: m,
                    highlight: true,
                    subtitle: 'Official boundary · discover buildings',
                    onTap: () => context.push('/mission/$projectId/eb/${m.id}'),
                  ),
                const SizedBox(height: 20),
              ],
              if (listing.isNotEmpty) ...[
                const Text('House Listing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final m in listing)
                  _MissionCard(
                    mission: m,
                    subtitle: '${m.totalBuildings} buildings · ${m.progressPercent.round()}% listed',
                    onTap: () => context.push('/mission/$projectId/eb/${m.id}'),
                  ),
                const SizedBox(height: 20),
              ],
              if (done.isNotEmpty) ...[
                const Text('Completed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                for (final m in done)
                  _MissionCard(
                    mission: m,
                    onTap: () => context.push('/mission/$projectId/eb/${m.id}'),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _importHloPdf(BuildContext context, WidgetRef ref) async {
    final eb = await ensureEnumeratorEb(ref, projectId);
    if (context.mounted) {
      context.push('/mission/$projectId/eb/${eb.id}/georef');
    }
  }
}

class _EmptyMissionState extends StatelessWidget {
  const _EmptyMissionState({required this.onImportPdf});
  final VoidCallback onImportPdf;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 64, color: AppTheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            const Text(
              'Start Your HLB Map',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Import your HLO PDF — the EB number is read from the map. '
              'Then align the boundary, walk the block, and mark every building.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onImportPdf,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import HLO PDF'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(220, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.onTap,
    this.highlight = false,
    this.subtitle,
  });

  final EnumerationBlock mission;
  final VoidCallback onTap;
  final bool highlight;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surfaceLight,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)) : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: highlight ? AppTheme.primary : AppTheme.surface,
          child: Text(
            mission.ebCode,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: highlight ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
        title: Text(
          mission.ebCode == kDefaultEbCode ? 'My HLB' : 'HLB ${mission.ebCode}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle ??
              (highlight
                  ? 'In progress'
                  : mission.status == 'draft'
                      ? 'HLB mapping'
                      : 'Complete'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

final ebListProvider = FutureProvider.family<List<EnumerationBlock>, String>((ref, projectId) async {
  final cloud = ref.watch(firebaseMissionRepositoryProvider);
  final pid = projectId.isNotEmpty ? projectId : FirebaseMissionRepository.defaultProjectId;
  return cloud.listEbs(pid);
});