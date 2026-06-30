import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../data/credit_service.dart';
import '../data/payment_service.dart';
import '../data/user_account_repository.dart';
import '../domain/user_credits.dart';

final userAccountRepositoryProvider = Provider<UserAccountRepository>((ref) {
  return UserAccountRepository();
});

final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService(ref.watch(userAccountRepositoryProvider));
});

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(accountRepo: ref.watch(userAccountRepositoryProvider));
});

final pricingConfigProvider = FutureProvider<PricingConfig>((ref) async {
  return ref.watch(userAccountRepositoryProvider).fetchPricing();
});

final userAccountProvider = StreamProvider<UserAccount?>((ref) {
  final auth = ref.watch(authStateProvider);
  final uid = auth.user?.id;
  if (uid == null) return const Stream.empty();
  final repo = ref.watch(userAccountRepositoryProvider);
  return repo.watchAccount(uid);
});

final creditHistoryProvider = StreamProvider<List<CreditHistoryEntry>>((ref) {
  final auth = ref.watch(authStateProvider);
  final uid = auth.user?.id;
  if (uid == null) return const Stream.empty();
  return ref.watch(userAccountRepositoryProvider).watchCreditHistory(uid);
});

/// Ensures Firestore user doc exists after login.
final ensureUserAccountProvider = FutureProvider<void>((ref) async {
  final auth = ref.watch(authStateProvider);
  final user = auth.user;
  if (user == null) return;
  await ref.watch(userAccountRepositoryProvider).ensureAccount(
        uid: user.id,
        email: user.email,
      );
});
