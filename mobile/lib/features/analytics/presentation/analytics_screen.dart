import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';

final analyticsProvider = FutureProvider.family<AnalyticsDashboard, String>((ref, projectId) async {
  final ebs = await ref.watch(firebaseMissionRepositoryProvider).listEbs(projectId);
  final totalBuildings = ebs.fold<int>(0, (sum, eb) => sum + eb.totalBuildings);
  final completed = ebs.fold<int>(0, (sum, eb) => sum + ((eb.progressPercent / 100) * eb.totalBuildings).round());
  final coverage = totalBuildings == 0 ? 0.0 : (completed / totalBuildings) * 100;
  return AnalyticsDashboard(
    coverage: coverage,
    totalAssets: totalBuildings,
    verifiedAssets: completed,
    pendingAssets: totalBuildings - completed,
    conflicts: 0,
    productivity: completed,
  );
});

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider(projectId));
    final user = ref.watch(authStateProvider).user;
    final isSupervisor = user?.role == UserRole.supervisor || user?.role == UserRole.admin;

    if (!isSupervisor) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const Center(
          child: Text('Supervisor access required', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dashboard) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CoverageCard(coverage: dashboard.coverage),
            const SizedBox(height: 16),
            _StatsGrid(dashboard: dashboard),
            const SizedBox(height: 16),
            _ConflictCard(count: dashboard.conflicts),
          ],
        ),
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  const _CoverageCard({required this.coverage});

  final double coverage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Listing coverage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: coverage / 100, minHeight: 8),
            const SizedBox(height: 8),
            Text('${coverage.toStringAsFixed(1)}% complete', style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.dashboard});

  final AnalyticsDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(label: 'Buildings', value: '${dashboard.totalAssets}')),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(label: 'Completed', value: '${dashboard.verifiedAssets}')),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(label: 'Pending', value: '${dashboard.pendingAssets}')),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined),
        title: const Text('Open conflicts'),
        subtitle: Text(count == 0 ? 'None on device' : '$count need review'),
      ),
    );
  }
}

class AnalyticsDashboard {
  const AnalyticsDashboard({
    required this.coverage,
    required this.totalAssets,
    required this.verifiedAssets,
    required this.pendingAssets,
    required this.conflicts,
    required this.productivity,
  });

  final double coverage;
  final int totalAssets;
  final int verifiedAssets;
  final int pendingAssets;
  final int conflicts;
  final int productivity;
}
