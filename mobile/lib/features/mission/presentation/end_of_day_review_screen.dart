import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import 'eb_list_screen.dart';
import 'mission_home_screen.dart';

class EndOfDayReviewScreen extends ConsumerWidget {
  const EndOfDayReviewScreen({
    required this.projectId,
    required this.ebId,
    this.latitude,
    this.longitude,
    super.key,
  });

  final String projectId;
  final String ebId;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(dayReviewProvider((
      ebId: ebId,
      lat: latitude,
      lng: longitude,
    )));

    return Scaffold(
      appBar: AppBar(title: const Text('End of Day Review')),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (review) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Today's Mission", style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              Text('EB ${review.ebCode}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              _CompletionRing(percent: review.progressPercent),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'You are ${review.progressPercent.toStringAsFixed(0)}% complete',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 28),
              _ReviewRow(label: 'Completed', value: '${review.completedBuildings}'),
              _ReviewRow(label: 'Remaining', value: '${review.remainingBuildings}'),
              _ReviewRow(
                label: 'Estimated time',
                value: review.remainingBuildings > 0 ? '~${review.estimatedRemainingMinutes} min' : 'Done!',
              ),
              if (review.remainingBuildingNumbers.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Remaining buildings', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in review.remainingBuildingNumbers)
                      Chip(
                        label: Text('$n'),
                        backgroundColor: AppTheme.pending.withValues(alpha: 0.15),
                      ),
                  ],
                ),
              ],
              const Spacer(),
              if (review.remainingBuildings > 0)
                ElevatedButton(
                  onPressed: () => context.go('/mission/$projectId/eb/$ebId'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('Continue Mission'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('End Day'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionRing extends StatelessWidget {
  const _CompletionRing({required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 120,
        height: 120,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 10,
              backgroundColor: AppTheme.surface,
              color: percent >= 90 ? AppTheme.verified : AppTheme.primary,
            ),
            Center(
              child: Text(
                '${percent.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

typedef DayReviewKey = ({String ebId, double? lat, double? lng});

final dayReviewProvider = FutureProvider.family<DayReview, DayReviewKey>((ref, key) async {
  return ref.watch(missionApiProvider).getDayReview(
        key.ebId,
        latitude: key.lat,
        longitude: key.lng,
      );
});
