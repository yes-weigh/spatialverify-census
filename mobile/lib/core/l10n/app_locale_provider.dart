import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../storage/secure_storage.dart';
import 'app_language.dart';
import 'app_strings.dart';

final appLanguageProvider = StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier(ref.watch(secureStorageProvider));
});

final appStringsProvider = Provider<AppStrings>((ref) {
  return AppStrings(ref.watch(appLanguageProvider));
});

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier(this._storage) : super(AppLanguage.fromCode(_storage.appLocaleCode));

  final SecureLocalStorage _storage;

  Future<void> toggle() async {
    await setLanguage(state.toggleTarget);
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (state == language) return;
    await _storage.setAppLocaleCode(language.storageCode);
    state = language;
  }
}
