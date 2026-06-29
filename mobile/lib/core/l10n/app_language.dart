import 'package:flutter/material.dart';

enum AppLanguage {
  en,
  ml;

  static const supportedLocales = [
    Locale('en'),
    Locale('ml'),
  ];

  Locale get locale => switch (this) {
        AppLanguage.en => const Locale('en'),
        AppLanguage.ml => const Locale('ml'),
      };

  String get storageCode => name;

  String get displayName => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.ml => 'മലയാളം',
      };

  AppLanguage get toggleTarget => switch (this) {
        AppLanguage.en => AppLanguage.ml,
        AppLanguage.ml => AppLanguage.en,
      };

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (l) => l.storageCode == code,
      orElse: () => AppLanguage.en,
    );
  }
}
