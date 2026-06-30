import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_credits.dart';
import 'licensing_providers.dart';

class CreditHistoryScreen extends ConsumerWidget {
  const CreditHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(creditHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Credit History')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Text('No credit activity yet', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = entries[index];
              final sign = e.amount >= 0 ? '+' : '';
              return ListTile(
                tileColor: AppTheme.surfaceLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(_label(e.type), style: const TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text(
                  _formatDate(e.createdAt),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                trailing: Text(
                  '$sign${e.amount}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: e.amount >= 0 ? AppTheme.verified : AppTheme.textPrimary,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _label(String type) {
    switch (type) {
      case 'consume':
        return 'Used credits';
      case 'daily_reset':
        return 'Daily free credits';
      case 'purchase_approved':
        return 'Purchase approved';
      case 'admin_grant':
        return 'Admin grant';
      default:
        return type;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
