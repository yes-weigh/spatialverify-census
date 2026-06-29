import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

final conflictsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.get('/survey/conflicts');
  return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
});

class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictsAsync = ref.watch(conflictsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conflicts')),
      body: conflictsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (conflicts) {
          if (conflicts.isEmpty) {
            return const Center(
              child: Text(
                'No open conflicts',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conflicts.length,
            itemBuilder: (context, index) {
              final conflict = conflicts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ConflictTile(
                  conflict: conflict,
                  onResolve: (resolution) async {
                    final api = ref.read(apiClientProvider);
                    await api.post('/survey/conflicts/${conflict['id']}/resolve', data: {
                      'resolution': resolution,
                    });
                    ref.invalidate(conflictsProvider);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.onResolve,
  });

  final Map<String, dynamic> conflict;
  final void Function(Map<String, dynamic> resolution) onResolve;

  @override
  Widget build(BuildContext context) {
    final submissionA = conflict['submission_a'] as Map<String, dynamic>;
    final submissionB = conflict['submission_b'] as Map<String, dynamic>;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conflict: ${conflict['entity_type']}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _SubmissionRow(label: 'Submission A', data: submissionA),
          const SizedBox(height: 8),
          _SubmissionRow(label: 'Submission B', data: submissionB),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onResolve(submissionA),
                  child: const Text('Accept A'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => onResolve(submissionB),
                  child: const Text('Accept B'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({required this.label, required this.data});

  final String label;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(
            data.toString(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
