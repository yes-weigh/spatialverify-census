import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'core/database/database.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/l10n/app_language.dart';
import 'core/l10n/app_locale_provider.dart';
import 'core/providers/providers.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/router.dart';
import 'features/mission/data/hlb_local_cache.dart';
import 'features/mission/presentation/mission_providers.dart';
import 'core/updates/app_update_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  final storage = SecureLocalStorage();
  await storage.init();

  await bootstrapFirebase();

  final hlbCache = HlbLocalCache();
  await hlbCache.init();

  final database = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        databaseProvider.overrideWithValue(database),
        hlbLocalCacheProvider.overrideWithValue(hlbCache),
      ],
      child: const SpatialVerifyApp(),
    ),
  );
}

class SpatialVerifyApp extends ConsumerWidget {
  const SpatialVerifyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(appLanguageProvider);

    return AppUpdateScope(
      child: MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: language.locale,
        supportedLocales: AppLanguage.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    );
  }
}
