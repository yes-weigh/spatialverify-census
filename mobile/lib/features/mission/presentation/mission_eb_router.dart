import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mission_game_map_screen.dart';
import 'mission_home_screen.dart';
import 'mission_providers.dart';
/// Routes to HLB mapping or house listing based on mission phase.
class MissionEbRouter extends ConsumerWidget {
  const MissionEbRouter({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(EbMissionQuery(ebId: ebId, projectId: projectId)));
    final launchPosition = ref.watch(appLaunchLocationProvider).valueOrNull;

    return discoveryAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (d) {
        if (d.phase == 'mapping') {
          return MissionGameMapScreen(
            projectId: projectId,
            ebId: ebId,
            initialPosition: launchPosition,
          );
        }
        return TodaysMissionScreen(projectId: projectId, ebId: ebId);
      },
    );
  }
}
