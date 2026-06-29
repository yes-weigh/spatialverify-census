import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import '../utils/mission_navigation.dart';
import '../widgets/bearing_arrow.dart';
import 'eb_list_screen.dart';
import 'mission_home_screen.dart';

class BuildingWorkflowScreen extends ConsumerStatefulWidget {
  const BuildingWorkflowScreen({
    required this.projectId,
    required this.ebId,
    required this.buildingId,
    super.key,
  });

  final String projectId;
  final String ebId;
  final String buildingId;

  @override
  ConsumerState<BuildingWorkflowScreen> createState() => _BuildingWorkflowScreenState();
}

class _BuildingWorkflowScreenState extends ConsumerState<BuildingWorkflowScreen> with MissionGpsTracking {
  bool _completing = false;
  bool _pinLearned = false;

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (pos) {
        if (!mounted) return;
        setState(() {});
        final route = ref.read(missionRouteProvider(widget.ebId)).valueOrNull;
        if (route == null || _pinLearned) return;
        MissionBuilding? building;
        for (final b in route) {
          if (b.id == widget.buildingId) {
            building = b;
            break;
          }
        }
        if (building == null || building.status != 'not_visited') return;
        if (!MissionNavigation.isArrived(pos, building)) return;
        _learnPinOnArrival(building, pos);
      },
    );
  }

  Future<void> _learnPinOnArrival(MissionBuilding building, Position pos) async {
    if (_pinLearned) return;
    _pinLearned = true;
    await ref.read(missionApiProvider).updateBuildingStatus(
          building.id,
          MissionBuildingStatus.visited,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
    ref.invalidate(missionRouteProvider(widget.ebId));
    ref.invalidate(missionDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(missionRouteProvider(widget.ebId));

    return Scaffold(
      appBar: AppBar(title: const Text('Building')),
      body: routeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (buildings) {
          MissionBuilding? building;
          for (final b in buildings) {
            if (b.id == widget.buildingId) {
              building = b;
              break;
            }
          }
          if (building == null) return const Center(child: Text('Building not found'));

          final distance = MissionNavigation.distanceLabel(position, building);
          final bearing = MissionNavigation.bearingDegrees(position, building);
          final arrived = MissionNavigation.isArrived(position, building);
          final hasPin = MissionNavigation.hasGpsPin(building);

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Building ${building.buildingNumber}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '(${building.censusHouseCount} Census ${building.censusHouseCount == 1 ? 'House' : 'Houses'})',
                  style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                ),
                if (hasPin || distance != null) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: BearingArrow(
                      targetBearing: bearing,
                      distanceLabel: distance,
                      isArrived: arrived,
                      size: 100,
                    ),
                  ),
                ],
                const Spacer(),
                if (_completing)
                  const Center(child: CircularProgressIndicator())
                else
                  ElevatedButton(
                    onPressed: arrived || building.status == 'visited' || building.status == 'completed'
                        ? () => _complete(ref, context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.verified,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: Text(
                      arrived ? 'Complete' : 'Walk closer to complete',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (!arrived && !hasPin) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'No GPS pin yet — use layout map, or complete when you arrive',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => _complete(ref, context, force: true),
                    child: const Text('Complete anyway'),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/scan/${widget.projectId}?ebId=${widget.ebId}&buildingId=${widget.buildingId}'),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Verify with camera (optional)'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _complete(WidgetRef ref, BuildContext context, {bool force = false}) async {
    setState(() => _completing = true);
    try {
      double? lat;
      double? lng;
      try {
        final pos = position ?? await Geolocator.getCurrentPosition();
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

      await ref.read(missionApiProvider).updateBuildingStatus(
            widget.buildingId,
            MissionBuildingStatus.completed,
            latitude: lat,
            longitude: lng,
          );
      ref.invalidate(missionRouteProvider(widget.ebId));
      ref.invalidate(missionDashboardProvider);
      ref.invalidate(missionCoverageProvider(widget.ebId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lat != null ? 'Building complete — GPS pin saved' : 'Building complete')),
        );
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }
}
