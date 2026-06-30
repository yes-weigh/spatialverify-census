import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/user_credits.dart';

class UserAccountRepository {
  UserAccountRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection('users').doc(uid);

  Stream<UserAccount?> watchAccount(String uid) {
    return _userRef(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return UserAccount.fromFirestore(uid, snap.data()!);
    });
  }

  Future<UserAccount> ensureAccount({
    required String uid,
    required String email,
    String? phone,
  }) async {
    final ref = _userRef(uid);
    final snap = await ref.get();
    if (snap.exists && snap.data() != null) {
      return UserAccount.fromFirestore(uid, snap.data()!);
    }

    final dailyLimit = PricingConfig.defaults.dailyFreeCredits;
    final now = Timestamp.fromDate(DateTime.now());
    final data = {
      'email': email,
      if (phone != null) 'phone': phone,
      'credits': {
        'dailyRemaining': dailyLimit,
        'dailyLimit': dailyLimit,
        'purchasedRemaining': 0,
        'totalPurchased': 0,
        'lastDailyReset': now,
      },
      'license': {
        'active': false,
        'plan': null,
        'expiresAt': null,
        'approvedAt': null,
      },
      'createdAt': now,
    };
    await ref.set(data);
    return UserAccount.fromFirestore(uid, data);
  }

  Future<PricingConfig> fetchPricing() async {
    final snap = await _firestore.collection('system').doc('pricing').get();
    return PricingConfig.fromMap(snap.data());
  }

  Stream<List<CreditHistoryEntry>> watchCreditHistory(String uid, {int limit = 50}) {
    return _userRef(uid)
        .collection('credit_history')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CreditHistoryEntry.fromFirestore(d.id, d.data()))
            .toList());
  }

  String? get currentUid => _auth.currentUser?.uid;
}
