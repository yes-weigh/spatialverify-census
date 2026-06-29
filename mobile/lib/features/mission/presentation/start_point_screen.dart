import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_directions_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hlb_geo_engine.dart';
import '../data/hlb_local_state.dart';
import '../data/mission_local_first_service.dart';
import '../models/layout_georef_models.dart';
import '../widgets/bearing_arrow.dart';
import '../widgets/mission_map_canvas.dart';
import '../widgets/mission_navigation_banner.dart';
import '../widgets/mission_satellite_map.dart';
import 'mission_providers.dart';

/// Navigate enumerator to the official NW start point — Google Maps bike route when configured.
class StartPointScreen extends ConsumerStatefulWidget {
  const StartPointScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<StartPointScreen> createState() => _StartPointScreenState();
}

class _StartPointScreenState extends ConsumerState<StartPointScreen> with MissionGpsTracking {
  static const _arrivalRadiusMeters = 25.0;

  LocalOfficialBoundary? _official;
  DirectionsRoute? _route;
  var _loadingRoute = false;
  var _stepIndex = 0;

  MissionLocalFirstService get _local => ref.read(missionLocalFirstProvider);
  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final state = await _local.getRawState(widget.ebId);
    if (mounted) {
      setState(() {
        _official = state?.officialBoundary;
        _loadingRoute = AppConfig.hasGoogleMaps;
      });
    }
    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (_) {
        _updateStepIndex();
        setState(() {});
      },
      onBreadcrumb: (_) {},
    );
  }

  void _updateStepIndex() {
    final route = _route;
    final pos = position;
    if (route == null || pos == null || route.steps.isEmpty) return;

    var nearest = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < route.steps.length; i++) {
      final end = route.steps[i].endLocation;
      final d = HlbGeoEngine.haversineMeters(pos.latitude, pos.longitude, end.latitude, end.longitude);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    if (nearest != _stepIndex) _stepIndex = nearest;
  }

  @override
  void dispose() {
    stopMissionGps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final official = _official;
    final pos = position;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        title: const Text('Navigate to HLB'),
        backgroundColor: Colors.transparent,
      ),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          if (!d.hasOfficialBoundary || official == null) {
            return const Center(
              child: Text('No official boundary loaded for this HLB', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }

          final dest = gmaps.LatLng(official.startLat, official.startLng);
          final userLatLng = pos != null ? LatLng(pos.latitude, pos.longitude) : null;
          final mapCenter = userLatLng ?? LatLng(official.startLat, official.startLng);
          final arrived = (pos != null &&
                  HlbGeoEngine.haversineMeters(pos.latitude, pos.longitude, dest.latitude, dest.longitude) <=
                      _arrivalRadiusMeters) ||
              d.startPointReached;

          final boundaryRing = official.ringLatLng.map((p) => GpsPoint(p.lat, p.lng)).toList();

          if (AppConfig.hasGoogleMaps) {
            return Stack(
              fit: StackFit.expand,
              children: [
                MissionMapCanvas(
                  center: mapCenter,
                  boundary: boundaryRing,
                  userPosition: userLatLng,
                  boundaryDrawProgress: 1,
                  mode: MissionMapMode.mission,
                  navigationDestination: dest,
                  navigationOrigin: pos != null ? gmaps.LatLng(pos.latitude, pos.longitude) : null,
                  onRouteLoaded: (route) => setState(() {
                    _route = route;
                    _loadingRoute = false;
                  }),
                ),
                if (arrived)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 120,
                    child: _ArrivedCard(onStart: () => _startDiscovery(context)),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MissionNavigationBanner(
                      route: _route,
                      currentStepIndex: _stepIndex,
                      loading: _loadingRoute,
                    ),
                  ),
              ],
            );
          }

          return _CompassFallback(
            bearing: d.startPointBearing,
            distanceLabel: d.startPointDistanceLabel,
            arrived: arrived,
            onStart: () => _startDiscovery(context),
          );
        },
      ),
    );
  }

  Future<void> _startDiscovery(BuildContext context) async {
    await _local.recordBoundaryAudit(widget.ebId, 'start_reached');
    await _local.recordBoundaryAudit(widget.ebId, 'discovery_started');
    if (context.mounted) {
      context.pushReplacement('/mission/${widget.projectId}/eb/${widget.ebId}');
    }
  }
}

class _ArrivedCard extends StatelessWidget {
  const _ArrivedCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF14141E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You have reached the official start point',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                ),
                child: const Text('OPEN MAP', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassFallback extends StatelessWidget {
  const _CompassFallback({
    required this.bearing,
    required this.distanceLabel,
    required this.arrived,
    required this.onStart,
  });

  final double? bearing;
  final String? distanceLabel;
  final bool arrived;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Reach the official start point',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Add GOOGLE_MAPS_API_KEY for satellite map + bike navigation',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          BearingArrow(
            targetBearing: bearing,
            distanceLabel: distanceLabel ?? '—',
            isArrived: arrived,
            size: 160,
          ),
          const Spacer(),
          if (arrived)
            _ArrivedCard(onStart: onStart)
          else
            Text(
              bearing != null ? 'Head ${HlbGeoEngine.cardinalLabel(bearing!)}' : 'Waiting for GPS…',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}
