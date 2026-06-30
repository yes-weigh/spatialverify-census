import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/premium_operation.dart';

Future<bool> showCreditConfirmDialog({
  required BuildContext context,
  required PremiumOperation operation,
  required int cost,
  required int remainingAfter,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(operation.label, style: const TextStyle(color: AppTheme.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Cost', '$cost Credits'),
          const SizedBox(height: 8),
          _row('Remaining after', '$remainingAfter'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
      ],
    ),
  ).then((v) => v ?? false);
}

Widget _row(String label, String value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
      Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
    ],
  );
}
