class UserCredits {
  const UserCredits({
    required this.dailyRemaining,
    required this.dailyLimit,
    required this.purchasedRemaining,
    required this.lastDailyReset,
    required this.totalPurchased,
  });

  final int dailyRemaining;
  final int dailyLimit;
  final int purchasedRemaining;
  final DateTime lastDailyReset;
  final int totalPurchased;

  int get totalAvailable => dailyRemaining + purchasedRemaining;

  factory UserCredits.initial({int dailyLimit = 10}) {
    final now = DateTime.now();
    return UserCredits(
      dailyRemaining: dailyLimit,
      dailyLimit: dailyLimit,
      purchasedRemaining: 0,
      lastDailyReset: _startOfIstDay(now),
      totalPurchased: 0,
    );
  }

  factory UserCredits.fromMap(Map<String, dynamic>? map) {
    if (map == null) return UserCredits.initial();
    return UserCredits(
      dailyRemaining: (map['dailyRemaining'] as num?)?.toInt() ?? 10,
      dailyLimit: (map['dailyLimit'] as num?)?.toInt() ?? 10,
      purchasedRemaining: (map['purchasedRemaining'] as num?)?.toInt() ?? 0,
      lastDailyReset: _timestampToDate(map['lastDailyReset']) ?? _startOfIstDay(DateTime.now()),
      totalPurchased: (map['totalPurchased'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'dailyRemaining': dailyRemaining,
        'dailyLimit': dailyLimit,
        'purchasedRemaining': purchasedRemaining,
        'lastDailyReset': lastDailyReset,
        'totalPurchased': totalPurchased,
      };

  UserCredits copyWith({
    int? dailyRemaining,
    int? dailyLimit,
    int? purchasedRemaining,
    DateTime? lastDailyReset,
    int? totalPurchased,
  }) {
    return UserCredits(
      dailyRemaining: dailyRemaining ?? this.dailyRemaining,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      purchasedRemaining: purchasedRemaining ?? this.purchasedRemaining,
      lastDailyReset: lastDailyReset ?? this.lastDailyReset,
      totalPurchased: totalPurchased ?? this.totalPurchased,
    );
  }

  static DateTime _startOfIstDay(DateTime instant) {
    final ist = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime.utc(ist.year, ist.month, ist.day).subtract(const Duration(hours: 5, minutes: 30));
  }

  static DateTime _timestampToDate(dynamic value) {
    if (value == null) return _startOfIstDay(DateTime.now());
    if (value is DateTime) return value;
    // Firestore Timestamp from cloud_firestore
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return _startOfIstDay(DateTime.now());
    }
  }

  bool needsDailyReset(DateTime now) {
    return _startOfIstDay(now).isAfter(lastDailyReset);
  }
}

class UserLicense {
  const UserLicense({
    required this.active,
    this.plan,
    this.expiresAt,
    this.approvedAt,
  });

  final bool active;
  final String? plan;
  final DateTime? expiresAt;
  final DateTime? approvedAt;

  factory UserLicense.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserLicense(active: false);
    return UserLicense(
      active: map['active'] == true,
      plan: map['plan'] as String?,
      expiresAt: _timestampToDateOrNull(map['expiresAt']),
      approvedAt: _timestampToDateOrNull(map['approvedAt']),
    );
  }
}

DateTime? _timestampToDateOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    return (value as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

class UserAccount {
  const UserAccount({
    required this.uid,
    required this.email,
    this.phone,
    required this.credits,
    required this.license,
  });

  final String uid;
  final String email;
  final String? phone;
  final UserCredits credits;
  final UserLicense license;

  int get totalCredits => credits.totalAvailable;

  factory UserAccount.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserAccount(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      phone: data['phone'] as String?,
      credits: UserCredits.fromMap(data['credits'] as Map<String, dynamic>?),
      license: UserLicense.fromMap(data['license'] as Map<String, dynamic>?),
    );
  }
}

class CreditPlan {
  const CreditPlan({
    required this.id,
    required this.label,
    required this.credits,
    required this.amountInr,
  });

  final String id;
  final String label;
  final int credits;
  final int amountInr;

  factory CreditPlan.fromMap(Map<String, dynamic> map) {
    return CreditPlan(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      credits: (map['credits'] as num?)?.toInt() ?? 0,
      amountInr: (map['amountInr'] as num?)?.toInt() ?? 0,
    );
  }
}

class PricingConfig {
  const PricingConfig({
    required this.upiId,
    required this.merchantName,
    required this.dailyFreeCredits,
    required this.plans,
  });

  final String upiId;
  final String merchantName;
  final int dailyFreeCredits;
  final List<CreditPlan> plans;

  static const defaults = PricingConfig(
    upiId: 'yourupi@okaxis',
    merchantName: 'SpatialVerify',
    dailyFreeCredits: 10,
    plans: [
      CreditPlan(id: 'pack_50', label: '50 Credits', credits: 50, amountInr: 499),
      CreditPlan(id: 'pack_120', label: '120 Credits', credits: 120, amountInr: 999),
      CreditPlan(id: 'pack_300', label: '300 Credits', credits: 300, amountInr: 1999),
    ],
  );

  factory PricingConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    final rawPlans = map['plans'] as List<dynamic>? ?? [];
    return PricingConfig(
      upiId: map['upiId'] as String? ?? defaults.upiId,
      merchantName: map['merchantName'] as String? ?? defaults.merchantName,
      dailyFreeCredits: (map['dailyFreeCredits'] as num?)?.toInt() ?? defaults.dailyFreeCredits,
      plans: rawPlans
          .whereType<Map<String, dynamic>>()
          .map(CreditPlan.fromMap)
          .where((p) => p.credits > 0)
          .toList(),
    );
  }
}

class CreditHistoryEntry {
  const CreditHistoryEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.operation,
    this.reference,
    this.balanceAfter,
  });

  final String id;
  final String type;
  final int amount;
  final DateTime createdAt;
  final String? operation;
  final String? reference;
  final Map<String, dynamic>? balanceAfter;

  factory CreditHistoryEntry.fromFirestore(String id, Map<String, dynamic> data) {
    return CreditHistoryEntry(
      id: id,
      type: data['type'] as String? ?? '',
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      createdAt: UserCredits._timestampToDate(data['createdAt']),
      operation: data['operation'] as String?,
      reference: data['reference'] as String?,
      balanceAfter: data['balanceAfter'] as Map<String, dynamic>?,
    );
  }
}
