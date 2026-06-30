import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/premium_operation.dart';
import '../domain/user_credits.dart';
import 'operation_cost_catalog.dart';
import 'user_account_repository.dart';

class InsufficientCreditsException implements Exception {
  InsufficientCreditsException(this.required, this.available);

  final int required;
  final int available;

  @override
  String toString() => 'Need $required credits, have $available';
}

class CreditService {
  CreditService(this._repo);

  final UserAccountRepository _repo;

  int checkCost(PremiumOperation operation) => OperationCostCatalog.cost(operation);

  bool canPerformOperation(UserAccount account, PremiumOperation operation) {
    final cost = checkCost(operation);
    return account.totalCredits >= cost;
  }

  int remainingAfter(UserAccount account, PremiumOperation operation) {
    return account.totalCredits - checkCost(operation);
  }

  /// Applies IST calendar-day reset if needed. Returns updated account snapshot.
  Future<UserAccount> resetDailyCreditsIfNeeded(UserAccount account) async {
    if (!account.credits.needsDailyReset(DateTime.now())) {
      return account;
    }

    final ref = FirebaseFirestore.instance.collection('users').doc(account.uid);
    final pricing = await _repo.fetchPricing();
    final dailyLimit = pricing.dailyFreeCredits;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final credits = UserCredits.fromMap(data['credits'] as Map<String, dynamic>?);
      if (!credits.needsDailyReset(DateTime.now())) return;

      final updated = credits.copyWith(
        dailyRemaining: dailyLimit,
        dailyLimit: dailyLimit,
        lastDailyReset: UserCredits.initial(dailyLimit: dailyLimit).lastDailyReset,
      );

      tx.update(ref, {
        'credits.dailyRemaining': updated.dailyRemaining,
        'credits.dailyLimit': updated.dailyLimit,
        'credits.lastDailyReset': Timestamp.fromDate(DateTime.now()),
      });

      final historyRef = ref.collection('credit_history').doc();
      tx.set(historyRef, {
        'type': 'daily_reset',
        'amount': dailyLimit,
        'balanceAfter': {
          'dailyRemaining': updated.dailyRemaining,
          'purchasedRemaining': updated.purchasedRemaining,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final refreshed = await ref.get();
    return UserAccount.fromFirestore(account.uid, refreshed.data()!);
  }

  Future<UserAccount> consumeCredits({
    required UserAccount account,
    required PremiumOperation operation,
  }) async {
    final cost = checkCost(operation);
    if (account.totalCredits < cost) {
      throw InsufficientCreditsException(cost, account.totalCredits);
    }

    final pricing = await _repo.fetchPricing();
    final ref = FirebaseFirestore.instance.collection('users').doc(account.uid);
    late UserCredits balanceAfter;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('User account missing');
      final data = snap.data()!;
      var credits = UserCredits.fromMap(data['credits'] as Map<String, dynamic>?);

      if (credits.needsDailyReset(DateTime.now())) {
        credits = credits.copyWith(
          dailyRemaining: pricing.dailyFreeCredits,
          dailyLimit: pricing.dailyFreeCredits,
          lastDailyReset: DateTime.now(),
        );
      }

      var remaining = cost;
      var daily = credits.dailyRemaining;
      var purchased = credits.purchasedRemaining;

      final fromDaily = remaining <= daily ? remaining : daily;
      daily -= fromDaily;
      remaining -= fromDaily;

      if (remaining > 0) {
        purchased -= remaining;
        remaining = 0;
      }

      balanceAfter = credits.copyWith(
        dailyRemaining: daily,
        purchasedRemaining: purchased,
      );

      tx.update(ref, {
        'credits.dailyRemaining': balanceAfter.dailyRemaining,
        'credits.purchasedRemaining': balanceAfter.purchasedRemaining,
        'credits.lastDailyReset': Timestamp.fromDate(balanceAfter.lastDailyReset),
      });

      final historyRef = ref.collection('credit_history').doc();
      tx.set(historyRef, {
        'type': 'consume',
        'amount': -cost,
        'operation': OperationCostCatalog.operationKey(operation),
        'balanceAfter': {
          'dailyRemaining': balanceAfter.dailyRemaining,
          'purchasedRemaining': balanceAfter.purchasedRemaining,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final refreshed = await ref.get();
    return UserAccount.fromFirestore(account.uid, refreshed.data()!);
  }

  Future<void> purchaseCredits({
    required String uid,
    required int credits,
  }) async {
    // Reserved for future Razorpay webhook — admin approval uses Cloud Function.
    throw UnimplementedError('Use payment request flow for manual purchases');
  }
}
