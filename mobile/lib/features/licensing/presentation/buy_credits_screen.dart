import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_credits.dart';
import 'licensing_providers.dart';

class BuyCreditsScreen extends ConsumerStatefulWidget {
  const BuyCreditsScreen({super.key});

  @override
  ConsumerState<BuyCreditsScreen> createState() => _BuyCreditsScreenState();
}

class _BuyCreditsScreenState extends ConsumerState<BuyCreditsScreen> {
  CreditPlan? _selectedPlan;
  String? _reference;
  final _txnController = TextEditingController();
  File? _screenshot;
  var _submitting = false;
  var _paymentLaunched = false;

  @override
  void dispose() {
    _txnController.dispose();
    super.dispose();
  }

  Future<void> _launchUpi(CreditPlan plan, PricingConfig pricing) async {
    final payment = ref.read(paymentServiceProvider);
    final reference = payment.generateReference();
    final uri = Uri.parse(payment.buildUpiUri(
      pricing: pricing,
      amountInr: plan.amountInr,
      reference: reference,
    ));

    setState(() {
      _reference = reference;
      _selectedPlan = plan;
      _paymentLaunched = true;
    });

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open a UPI app. Install Google Pay, PhonePe, or Paytm.')),
        );
      }
    }
  }

  Future<void> _pickScreenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _screenshot = File(picked.path));
  }

  Future<void> _submit() async {
    final plan = _selectedPlan;
    final reference = _reference;
    if (plan == null || reference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a payment first by choosing a plan.')),
      );
      return;
    }
    if (_txnController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your UPI transaction ID.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final payment = ref.read(paymentServiceProvider);
      await payment.createPaymentRequest(
        plan: plan,
        reference: reference,
        upiTransactionId: _txnController.text.trim(),
        screenshot: _screenshot,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Payment submitted'),
          content: const Text(
            'Your payment is pending admin verification. Credits will appear automatically once approved.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmPaymentSuccess() async {
    if (!_paymentLaunched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Launch payment first, then confirm.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Did payment succeed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('YES')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pricingAsync = ref.watch(pricingConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Buy Credits')),
      body: pricingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (pricing) {
          final plans = pricing.plans.isEmpty ? PricingConfig.defaults.plans : pricing.plans;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Purchased credits never expire. Daily free credits are used first.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              ...plans.map((plan) => _planCard(plan, pricing)),
              if (_reference != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment reference', style: TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      SelectableText(
                        _reference!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Include this reference in your UPI note if your app allows editing.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _confirmPaymentSuccess,
                  child: const Text('I completed payment'),
                ),
                if (_paymentLaunched) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _txnController,
                    decoration: const InputDecoration(
                      labelText: 'UPI Transaction ID',
                      hintText: 'e.g. 419235847192',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickScreenshot,
                          icon: const Icon(Icons.image_outlined),
                          label: Text(_screenshot == null ? 'Screenshot (optional)' : 'Screenshot added'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit for verification'),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _planCard(CreditPlan plan, PricingConfig pricing) {
    final selected = _selectedPlan?.id == plan.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _launchUpi(plan, pricing),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.primary : AppTheme.glassBorder,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${plan.credits} credits',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${plan.amountInr}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
