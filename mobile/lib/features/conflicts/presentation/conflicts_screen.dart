import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

final conflictsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async => []);

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
              return Card(
                child: ListTile(
                  title: Text(conflict['title'] as String? ?? 'Conflict'),
                  subtitle: Text(conflict['description'] as String? ?? ''),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
