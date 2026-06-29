import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'core/database/database.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/providers/providers.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/router.dart';
import 'features/mission/data/hlb_local_cache.dart';
import 'features/mission/presentation/mission_providers.dart';

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

  if (AppConfig.useFirebase) {
    await bootstrapFirebase();
  }

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

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
