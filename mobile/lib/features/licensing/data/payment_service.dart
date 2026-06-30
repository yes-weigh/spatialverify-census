import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/user_credits.dart';
import 'user_account_repository.dart';

class PaymentService {
  PaymentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    UserAccountRepository? accountRepo,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _accountRepo = accountRepo ?? UserAccountRepository();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final UserAccountRepository _accountRepo;

  String generateReference() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final suffix = (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
    return 'SV-$date-$suffix';
  }

  String buildUpiUri({
    required PricingConfig pricing,
    required int amountInr,
    required String reference,
  }) {
    final params = {
      'pa': pricing.upiId,
      'pn': pricing.merchantName,
      'am': amountInr.toString(),
      'cu': 'INR',
      'tn': reference,
    };
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }

  Future<String> createPaymentRequest({
    required CreditPlan plan,
    required String reference,
    required String upiTransactionId,
    File? screenshot,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');

    String? storagePath;
    if (screenshot != null) {
      final requestId = _firestore.collection('payment_requests').doc().id;
      storagePath = 'payment-screenshots/${user.uid}/$requestId.jpg';
      await _storage.ref(storagePath).putFile(
            screenshot,
            SettableMetadata(contentType: 'image/jpeg'),
          );
    }

    final requestRef = _firestore.collection('payment_requests').doc();
    final deviceInfo = await _deviceInfo();
    final appVersion = await _appVersion();

    await requestRef.set({
      'uid': user.uid,
      'email': user.email ?? '',
      'phone': user.phoneNumber,
      'reference': reference,
      'upiTransactionId': upiTransactionId.trim(),
      'amount': plan.amountInr,
      'creditsRequested': plan.credits,
      'planId': plan.id,
      if (storagePath != null) 'screenshotStoragePath': storagePath,
      'status': 'PENDING',
      'deviceInfo': deviceInfo,
      'appVersion': appVersion,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return requestRef.id;
  }

  Future<Map<String, String>> _deviceInfo() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return {
        'platform': 'android',
        'model': info.model,
        'brand': info.brand,
        'sdk': info.version.sdkInt.toString(),
      };
    }
    return {'platform': 'other'};
  }

  Future<String> _appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  Future<PricingConfig> pricing() => _accountRepo.fetchPricing();
}
