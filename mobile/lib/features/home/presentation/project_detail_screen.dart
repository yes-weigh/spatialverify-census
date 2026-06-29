import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../mission/presentation/eb_list_screen.dart';

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(ebListProvider(projectId));

    return Scaffold(
      appBar: AppBar(title: const Text('Project')),
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
                  title: 'Continue ${m.ebCode}',
                  subtitle: '${((m.progressPercent / 100) * m.totalBuildings).round()}/${m.totalBuildings} buildings done',
                  actionLabel: 'Resume',
                  ebId: m.id,
                );
              }
              return _MissionHeroCard(
                projectId: projectId,
                title: 'Today\'s Mission',
                subtitle: 'Upload your Layout Map and walk your EB',
                actionLabel: 'New Mission',
              );
            },
          ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
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
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
