import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/models.dart';

final analyticsProvider = FutureProvider.family<AnalyticsDashboard, String>((ref, projectId) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.get('/survey/analytics/$projectId');
  return AnalyticsDashboard.fromJson(response.data as Map<String, dynamic>);
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: coverage / 100,
                    strokeWidth: 8,
                    backgroundColor: AppTheme.surfaceLight,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  '${coverage.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Survey Coverage',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.dashboard});

  final AnalyticsDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard('Verified', dashboard.verified, AppTheme.verified),
        _StatCard('Pending', dashboard.pending, AppTheme.pending),
        _StatCard('Rejected', dashboard.rejected, AppTheme.rejected),
        _StatCard('Not Surveyed', dashboard.notSurveyed, AppTheme.notSurveyed),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: color),
          ),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration(),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: count > 0 ? AppTheme.pending : AppTheme.verified,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Open Conflicts',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Text(
                  'Requires supervisor review',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
