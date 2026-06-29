import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../mission/presentation/eb_list_screen.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(ebListProvider(projectId));
    final syncState = ref.watch(syncStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Project'),
        actions: [
          if (syncState.isSyncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () => ref.read(syncStateProvider.notifier).sync(projectId),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          missionsAsync.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => _MissionHeroCard(
              projectId: projectId,
              title: 'Today\'s Mission',
              subtitle: 'Upload your Layout Map and walk your EB',
              actionLabel: 'New Mission',
            ),
            data: (missions) {
              final active = missions.where((m) => m.status == 'published' && !m.isComplete).toList();
              if (active.isNotEmpty) {
                final m = active.first;
                return _MissionHeroCard(
                  projectId: projectId,
                  title: 'Today\'s Mission',
                  subtitle: 'EB ${m.ebCode} • ${m.progressPercent.round()}% complete',
                  actionLabel: 'Continue',
                  ebId: m.id,
                );
              }
              return _MissionHeroCard(
                projectId: projectId,
                title: 'Today\'s Mission',
                subtitle: missions.isEmpty
                    ? 'Upload your Layout Map to begin'
                    : 'Set up or start your next EB',
                actionLabel: missions.isEmpty ? 'Upload Layout Map' : 'My Missions',
              );
            },
          ),
          const SizedBox(height: 16),
          _SecondaryActions(projectId: projectId),
        ],
      ),
    );
  }
}

class _MissionHeroCard extends StatelessWidget {
  const _MissionHeroCard({
    required this.projectId,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.ebId,
  });

  final String projectId;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String? ebId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF00897B).withValues(alpha: 0.25), AppTheme.surfaceLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00897B).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: Color(0xFF00897B), size: 28),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (ebId != null) {
                  context.push('/mission/$projectId/eb/$ebId');
                } else {
                  context.push('/mission/$projectId');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        ListTile(
          tileColor: AppTheme.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('Building verification'),
          subtitle: const Text('Optional identity check after reaching a building'),
          onTap: () => context.push('/scan/$projectId'),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: AppTheme.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.map_outlined),
          title: const Text('Map view'),
          onTap: () => context.push('/map/$projectId'),
        ),
      ],
    );
  }
}
