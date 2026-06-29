import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../utils/mission_navigation.dart';
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
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0D0D14),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4285F4)),
              SizedBox(height: 16),
              Text(
                'Finding your location…',
                style: TextStyle(color: AppTheme.textSecondary),
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
