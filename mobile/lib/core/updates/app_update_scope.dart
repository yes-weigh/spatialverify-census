import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'app_release_info.dart';
import 'app_update_dialog.dart';

/// Checks for OTA updates after sign-in and when the app resumes.
class AppUpdateScope extends ConsumerStatefulWidget {
  const AppUpdateScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateScope> createState() => _AppUpdateScopeState();
}

class _AppUpdateScopeState extends ConsumerState<AppUpdateScope> with WidgetsBindingObserver {
  StreamSubscription<AppReleaseInfo?>? _releaseSub;
  int? _promptedBuild;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkOnce();
    }
  }

  void _onSignedIn() {
    _startWatching();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnce());
  }

  void _onSignedOut() {
    _stopWatching();
    _promptedBuild = null;
  }

  void _startWatching() {
    if (kIsWeb || _releaseSub != null) return;
    final service = ref.read(appUpdateServiceProvider);
    _releaseSub = service.watchForUpdate().listen(_maybePrompt);
  }

  void _stopWatching() {
    _releaseSub?.cancel();
    _releaseSub = null;
  }

  Future<void> _checkOnce() async {
    if (kIsWeb || !ref.read(authStateProvider).isAuthenticated) return;
    final service = ref.read(appUpdateServiceProvider);
    final release = await service.checkForUpdate();
    if (!mounted || release == null) return;
    _maybePrompt(release);
  }

  void _maybePrompt(AppReleaseInfo? release) {
    if (!mounted || release == null) return;
    if (_promptedBuild == release.buildNumber) return;
    _promptedBuild = release.buildNumber;
    AppUpdateDialog.show(
      context,
      release: release,
      updateService: ref.read(appUpdateServiceProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.isAuthenticated && previous?.isAuthenticated != true) {
        _onSignedIn();
      } else if (!next.isAuthenticated && previous?.isAuthenticated == true) {
        _onSignedOut();
      }
    });

    if (ref.watch(authStateProvider).isAuthenticated && _releaseSub == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSignedIn());
    }

    return widget.child;
  }
}

/// Manual check from settings / about UI.
Future<void> checkForAppUpdateManually(BuildContext context, WidgetRef ref) async {
  if (kIsWeb) return;

  if (!ref.read(authStateProvider).isAuthenticated) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to check for updates')),
    );
    return;
  }

  final service = ref.read(appUpdateServiceProvider);
  final release = await service.checkForUpdate();
  if (!context.mounted) return;

  if (release == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You are on the latest version')),
    );
    return;
  }

  await AppUpdateDialog.show(
    context,
    release: release,
    updateService: service,
  );
}
