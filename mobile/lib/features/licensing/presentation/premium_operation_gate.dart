import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/credit_service.dart';
import '../data/operation_cost_catalog.dart';
import '../domain/premium_operation.dart';
import '../domain/user_credits.dart';
import 'buy_credits_screen.dart';
import 'credit_confirm_dialog.dart';
import 'licensing_providers.dart';

/// Runs a premium operation after credit confirmation and deduction.
class PremiumOperationGate {
  static Future<bool> run(
    BuildContext context,
    WidgetRef ref,
    PremiumOperation operation,
    Future<void> Function() action,
  ) async {
    final accountAsync = ref.read(userAccountProvider);
    var account = accountAsync.valueOrNull;
    if (account == null) {
      await ref.read(ensureUserAccountProvider.future);
      account = await ref.read(userAccountProvider.future);
    }
    if (account == null) return false;

    final creditService = ref.read(creditServiceProvider);
    account = await creditService.resetDailyCreditsIfNeeded(account);

    final cost = creditService.checkCost(operation);
    if (!creditService.canPerformOperation(account, operation)) {
      if (!context.mounted) return false;
      await _showInsufficientSheet(context, ref, operation);
      return false;
    }

    if (!context.mounted) return false;
    final confirmed = await showCreditConfirmDialog(
      context: context,
      operation: operation,
      cost: cost,
      remainingAfter: creditService.remainingAfter(account, operation),
    );
    if (!confirmed) return false;

    try {
      account = await creditService.consumeCredits(account: account, operation: operation);
      await action();
      return true;
    } on InsufficientCreditsException {
      if (context.mounted) {
        await _showInsufficientSheet(context, ref, operation);
      }
      return false;
    }
  }

  static Future<void> _showInsufficientSheet(
    BuildContext context,
    WidgetRef ref,
    PremiumOperation operation,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mission Credits Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              'You can continue using the app and viewing all existing missions.\n\n'
              '${operation.label} requires ${OperationCostCatalog.cost(operation)} credits.',
              style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 8),
            const Text('Remaining: 0', style: TextStyle(color: AppTheme.pending, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BuyCreditsScreen()),
                );
              },
              child: const Text('Buy Credits'),
            ),
          ],
        ),
      ),
    );
  }
}
