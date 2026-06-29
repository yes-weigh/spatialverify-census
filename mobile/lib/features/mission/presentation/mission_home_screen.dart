import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import '../utils/mission_navigation.dart';
import '../widgets/bearing_arrow.dart';
import 'eb_list_screen.dart';
import 'end_of_day_review_screen.dart';

/// The core enumerator screen — personal mission assistant.
class TodaysMissionScreen extends ConsumerStatefulWidget {
  const TodaysMissionScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<TodaysMissionScreen> createState() => _TodaysMissionScreenState();
}

class _TodaysMissionScreenState extends ConsumerState<TodaysMissionScreen> with MissionGpsTracking {
  final _arrivalHandled = <String>{};
  bool _learningPin = false;

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: _onPositionUpdate,
      onBreadcrumb: (pos) {
        ref.read(missionApiProvider).addBreadcrumb(
              widget.ebId,
              pos.latitude,
              pos.longitude,
              accuracy: pos.accuracy,
            );
      },
    );
  }

  void _onPositionUpdate(Position pos) {
    final key = _dashboardKey(pos);
    final dashboard = ref.read(missionDashboardProvider(key)).valueOrNull;
    final current = dashboard?.nextBuilding;
    if (current == null || _arrivalHandled.contains(current.id)) return;
    if (!MissionNavigation.isArrived(pos, current)) return;
    if (current.status != 'not_visited') {
      _arrivalHandled.add(current.id);
      return;
    }
    _handleArrival(current, pos);
  }

  Future<void> _handleArrival(MissionBuilding building, Position pos) async {
    if (_learningPin || _arrivalHandled.contains(building.id)) return;
    _arrivalHandled.add(building.id);
    setState(() => _learningPin = true);
    try {
      await ref.read(missionApiProvider).updateBuildingStatus(
            building.id,
            MissionBuildingStatus.visited,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
      ref.invalidate(missionRouteProvider(widget.ebId));
      ref.invalidate(missionDashboardProvider(_dashboardKey(pos)));
      ref.invalidate(missionCoverageProvider(widget.ebId));
    } finally {
      if (mounted) setState(() => _learningPin = false);
    }
  }

  DashboardKey _dashboardKey([Position? pos]) => (
        ebId: widget.ebId,
        lat: _roundCoord(pos?.latitude ?? position?.latitude),
        lng: _roundCoord(pos?.longitude ?? position?.longitude),
      );

  double? _roundCoord(double? v) => v == null ? null : (v * 500).round() / 500;

  @override
  Widget build(BuildContext context) {
    final dashKey = _dashboardKey();
    final dashboardAsync = ref.watch(missionDashboardProvider(dashKey));
    final coverageAsync = ref.watch(missionCoverageProvider(widget.ebId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Mission"),
        actions: [
          IconButton(
            icon: const Icon(Icons.nightlight_round_outlined),
            tooltip: 'End of day review',
            onPressed: () => context.push(
              '/mission/${widget.projectId}/eb/${widget.ebId}/end-day'
              '?lat=${position?.latitude ?? ''}&lng=${position?.longitude ?? ''}',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'All missions',
            onPressed: () => context.push('/mission/${widget.projectId}'),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit layout map',
            onPressed: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/edit'),
          ),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dashboard) {
          final current = dashboard.nextBuilding;
          final distance = MissionNavigation.distanceLabel(position, current);
          final bearing = MissionNavigation.bearingDegrees(position, current);
          final arrived = MissionNavigation.isArrived(position, current);
          final hasPin = current != null && MissionNavigation.hasGpsPin(current);
          final coverage = coverageAsync.valueOrNull;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(missionDashboardProvider(dashKey));
              ref.invalidate(missionCoverageProvider(widget.ebId));
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('EB ${dashboard.ebCode}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                _StatsRow(
                  buildings: dashboard.totalBuildings,
                  completed: dashboard.completedBuildings,
                  remaining: dashboard.remainingBuildings,
                ),
                const SizedBox(height: 20),
                if (coverage != null) _CoverageBanner(coverage: coverage),
                const SizedBox(height: 20),
                if (current != null)
                  _CurrentBuildingCard(
                    building: current,
                    distance: distance,
                    bearing: bearing,
                    isArrived: arrived,
                    hasGpsPin: hasPin,
                    learningPin: _learningPin,
                    strategy: dashboard.nextBuildingStrategy,
                    onGo: () => _openBuilding(context, current),
                  )
                else if (dashboard.totalBuildings > 0)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.glassDecoration(),
                    child: const Column(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppTheme.verified, size: 48),
                        SizedBox(height: 12),
                        Text('EB Complete!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('All buildings surveyed.', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.glassDecoration(),
                    child: Column(
                      children: [
                        const Text('Set up your layout map first'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/edit'),
                          child: const Text('Upload Layout Map'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Route List', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  children: [
                    ref.watch(missionRouteProvider(widget.ebId)).when(
                          loading: () => const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                          error: (e, _) => Text('$e'),
                          data: (buildings) => Column(
                            children: [
                              for (final b in buildings)
                                ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: missionStatusColor(b.status),
                                    child: Text('${b.buildingNumber}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  ),
                                  title: Text('Building ${b.label}'),
                                  subtitle: Text(
                                    b.status == 'not_visited'
                                        ? 'Never visited'
                                        : b.status.replaceAll('_', ' '),
                                  ),
                                  trailing: MissionNavigation.hasGpsPin(b)
                                      ? const Icon(Icons.gps_fixed, size: 16, color: AppTheme.verified)
                                      : null,
                                  onTap: () => _openBuilding(context, b),
                                ),
                            ],
                          ),
                        ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openBuilding(BuildContext context, MissionBuilding building) {
    context.push('/mission/${widget.projectId}/eb/${widget.ebId}/building/${building.id}');
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.buildings, required this.completed, required this.remaining});
  final int buildings;
  final int completed;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatBox(label: 'Buildings', value: '$buildings')),
        const SizedBox(width: 8),
        Expanded(child: _StatBox(label: 'Completed', value: '$completed')),
        const SizedBox(width: 8),
        Expanded(child: _StatBox(label: 'Remaining', value: '$remaining')),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: AppTheme.glassDecoration(radius: 12),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CoverageBanner extends StatelessWidget {
  const _CoverageBanner({required this.coverage});
  final Map<String, dynamic> coverage;

  @override
  Widget build(BuildContext context) {
    final percent = (coverage['coveragePercent'] as num?)?.toDouble() ?? 0;
    final notVisited = coverage['notVisitedBuildings'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: percent >= 100 ? AppTheme.verified.withValues(alpha: 0.12) : AppTheme.pending.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Coverage', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${percent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: percent / 100),
          if (notVisited.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Missed buildings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.pending)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final b in notVisited.take(12))
                  Chip(
                    label: Text('Bldg ${b['building_number'] ?? b['buildingNumber'] ?? '?'}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.pending.withValues(alpha: 0.15),
                  ),
              ],
            ),
            if (notVisited.length > 12)
              Text('+ ${notVisited.length - 12} more', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _CurrentBuildingCard extends StatelessWidget {
  const _CurrentBuildingCard({
    required this.building,
    required this.onGo,
    this.distance,
    this.bearing,
    this.isArrived = false,
    this.hasGpsPin = false,
    this.learningPin = false,
    this.strategy,
  });

  final MissionBuilding building;
  final VoidCallback onGo;
  final String? distance;
  final double? bearing;
  final bool isArrived;
  final bool hasGpsPin;
  final bool learningPin;
  final String? strategy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.2), AppTheme.primary.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                if (strategy == 'nearest')
                  const Text('Nearest remaining', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                Text('Building ${building.buildingNumber}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                Text(
                  '(${building.censusHouseCount} Census ${building.censusHouseCount == 1 ? 'House' : 'Houses'})',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (hasGpsPin || distance != null)
            BearingArrow(
              targetBearing: bearing,
              distanceLabel: distance,
              isArrived: isArrived,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.map_outlined, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your layout map to find this building.\nGPS pin saves on arrival or completion.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          if (learningPin)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Saving GPS pin…', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          if (isArrived && !learningPin)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('GPS pin saved for this building', style: TextStyle(fontSize: 12, color: AppTheme.verified)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onGo,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(isArrived ? 'Complete Building' : 'Go to Building'),
            ),
          ),
        ],
      ),
    );
  }
}

typedef DashboardKey = ({String ebId, double? lat, double? lng});

final missionDashboardProvider = FutureProvider.family<MissionDashboard, DashboardKey>((ref, key) async {
  return ref.watch(missionApiProvider).getDashboard(
        key.ebId,
        latitude: key.lat,
        longitude: key.lng,
      );
});

final missionRouteProvider = FutureProvider.family<List<MissionBuilding>, String>((ref, ebId) async {
  return ref.watch(missionApiProvider).getRoute(ebId);
});

final missionCoverageProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, ebId) async {
  return ref.watch(missionApiProvider).getCoverage(ebId);
});

typedef MissionHomeScreen = TodaysMissionScreen;
