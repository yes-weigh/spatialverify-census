import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_credits.dart';
import 'buy_credits_screen.dart';
import 'credit_history_screen.dart';
import 'licensing_providers.dart';

class CreditsAppBarAction extends ConsumerWidget {
  const CreditsAppBarAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(userAccountProvider);

    return accountAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (account) {
        final total = account?.totalCredits ?? 0;
        final color = total > 0 ? AppTheme.verified : AppTheme.pending;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: () => _openCreditsSheet(context, ref),
            icon: Icon(Icons.bolt, size: 18, color: color),
            label: Text(
              '$total',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  void _openCreditsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const CreditsSheet(),
    );
  }
}

class CreditsSheet extends ConsumerWidget {
  const CreditsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(userAccountProvider);

    return accountAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
      data: (account) {
        final credits = account?.credits ?? UserCredits.initial();
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mission Credits',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 20),
              _statTile('Today\'s free', '${credits.dailyLimit}', subtitle: 'Remaining ${credits.dailyRemaining}'),
              const SizedBox(height: 12),
              _statTile('Purchased', '${credits.purchasedRemaining}', subtitle: 'Never expires'),
              const SizedBox(height: 12),
              _statTile('Total available', '${credits.totalAvailable}', highlight: true),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CreditHistoryScreen()),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('History'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BuyCreditsScreen()),
                  );
                },
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Buy Credits'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statTile(String title, String value, {String? subtitle, bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppTheme.textSecondary)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: highlight ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
