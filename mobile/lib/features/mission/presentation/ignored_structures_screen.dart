import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hlb_local_state.dart';
import '../data/mission_local_first_service.dart';
import 'mission_providers.dart';

/// Review AI suggestions the enumerator ignored — common source of missed buildings.
class IgnoredStructuresScreen extends ConsumerWidget {
  const IgnoredStructuresScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  EbMissionQuery get _query => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(hlbAnalyticsProvider(_query));
    final local = ref.read(missionLocalFirstProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        title: const Text('Review Ignored Structures'),
        backgroundColor: Colors.transparent,
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (a) {
          if (a.ignoredSuggestions.isEmpty) {
            return const Center(
              child: Text('No ignored suggestions — good coverage discipline', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: a.ignoredSuggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _IgnoredTile(
              suggestion: a.ignoredSuggestions[i],
              onConfirm: () => _confirm(context, ref, local, a.ignoredSuggestions[i]),
              onDismiss: () => _dismiss(ref, local, a.ignoredSuggestions[i].id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, MissionLocalFirstService local, LocalIgnoredSuggestion s) async {
    await local.quickConfirmStructure(ebId, latitude: s.latitude, longitude: s.longitude);
    await local.dismissIgnoredSuggestion(ebId, s.id);
    ref.invalidate(hlbAnalyticsProvider(_query));
    ref.invalidate(discoveryStatusProvider(_query));
    ref.invalidate(draftMapProvider(_query));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Structure confirmed from ignored list'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _dismiss(WidgetRef ref, MissionLocalFirstService local, String id) async {
    await local.dismissIgnoredSuggestion(ebId, id);
    ref.invalidate(hlbAnalyticsProvider(_query));
  }
}

class _IgnoredTile extends StatelessWidget {
  const _IgnoredTile({required this.suggestion, required this.onConfirm, required this.onDismiss});

  final LocalIgnoredSuggestion suggestion;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_off, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  suggestion.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (suggestion.timesIgnored > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('×${suggestion.timesIgnored}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ignored at ${suggestion.latitude.toStringAsFixed(5)}, ${suggestion.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black),
                  child: const Text('Confirm Structure'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onDismiss, child: const Text('Keep Ignored')),
            ],
          ),
        ],
      ),
    );
  }
}
