import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';

class SecureLocalStorage {
  SecureLocalStorage({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  static const _keyName = 'spatialverify_encryption_key';
  Box<dynamic>? _settingsBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _settingsBox = await Hive.openBox('settings');
    await _ensureEncryptionKey();
  }

  Future<void> _ensureEncryptionKey() async {
    var key = await _secureStorage.read(key: _keyName);
    if (key == null) {
      final newKey = enc.Key.fromSecureRandom(32);
      key = base64Encode(newKey.bytes);
      await _secureStorage.write(key: _keyName, value: key);
    }
  }

  enc.Encrypter get _encrypter {
    final keyBase64 = _secureStorage.read(key: _keyName);
    return enc.Encrypter(enc.AES(enc.Key.fromBase64(keyBase64 as String)));
  }

  Future<String> encryptData(String plainText) async {
    final keyStr = await _secureStorage.read(key: _keyName);
    final key = enc.Key.fromBase64(keyStr!);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  Future<String> decryptData(String encryptedText) async {
    final parts = encryptedText.split(':');
    final keyStr = await _secureStorage.read(key: _keyName);
    final key = enc.Key.fromBase64(keyStr!);
    final iv = enc.IV.fromBase64(parts[0]);
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
  }

  String? get deviceId => _settingsBox?.get('device_id') as String?;

  Future<void> setDeviceId(String id) async {
    await _settingsBox?.put('device_id', id);
  }

  String? get selectedProjectId => _settingsBox?.get('selected_project_id') as String?;

  Future<void> setSelectedProjectId(String? id) async {
    if (id != null) {
      await _settingsBox?.put('selected_project_id', id);
    } else {
      await _settingsBox?.delete('selected_project_id');
    }
  }

  DateTime? get lastSyncAt {
    final ts = _settingsBox?.get('last_sync_at') as int?;
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  Future<void> setLastSyncAt(DateTime time) async {
    await _settingsBox?.put('last_sync_at', time.millisecondsSinceEpoch);
  }

  bool get isOfflineMode => _settingsBox?.get('offline_mode', defaultValue: false) as bool;

  Future<void> setOfflineMode(bool value) async {
    await _settingsBox?.put('offline_mode', value);
  }

  String get appLocaleCode => _settingsBox?.get('app_locale', defaultValue: 'en') as String;

  Future<void> setAppLocaleCode(String code) async {
    await _settingsBox?.put('app_locale', code);
  }
}
