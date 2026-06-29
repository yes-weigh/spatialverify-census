import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/providers.dart';
import '../../../core/brand/app_brand.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_logo.dart';
import 'mission_game_map_screen.dart';
import 'mission_home_screen.dart';
import 'mission_providers.dart';

/// Post-login home — HLB mapping first, house listing second.
class MissionLandingScreen extends ConsumerWidget {
  const MissionLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launchLocAsync = ref.watch(appLaunchLocationProvider);

    return launchLocAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppBrand.ink,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 72, useRasterIcon: true, withGlow: true),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: AppBrand.accent),
              const SizedBox(height: 16),
              Text(
                AppBrand.taglineShort,
                style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
      ),
      error: (_, __) => const _MissionHomeBody(initialPosition: null),
      data: (initialPosition) => _MissionHomeBody(initialPosition: initialPosition),
    );
  }
}

class _MissionHomeBody extends ConsumerWidget {
  const _MissionHomeBody({this.initialPosition});

  final Position? initialPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeMissionProvider);

    return activeAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('HLB Mission')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (active) {
        if (active != null) {
          if (active.phase == 'mapping') {
            return MissionGameMapScreen(
              projectId: active.projectId,
              ebId: active.ebId,
              initialPosition: initialPosition,
            );
          }
          return TodaysMissionScreen(projectId: active.projectId, ebId: active.ebId);
        }
        return _MissionStartScreen(initialPosition: initialPosition);
      },
    );
  }
}

class _MissionStartScreen extends ConsumerWidget {
  const _MissionStartScreen({this.initialPosition});

  final Position? initialPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);

    return projectsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (projects) {
        if (projects.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No project available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
          );
        }

        if (projects.length == 1) {
          return MissionMapLobbyScreen(
            projectId: projects.first.id,
            initialPosition: initialPosition,
          );
        }

        return MissionMapLobbyScreen(initialPosition: initialPosition);
      },
    );
  }
}
