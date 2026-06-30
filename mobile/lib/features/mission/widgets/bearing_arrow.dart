import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../utils/mission_navigation.dart';

/// Compass-style arrow pointing toward the target building.
class BearingArrow extends StatefulWidget {
  const BearingArrow({
    required this.targetBearing,
    this.distanceLabel,
    this.isArrived = false,
    this.size = 120,
    super.key,
  });

  final double? targetBearing;
  final String? distanceLabel;
  final bool isArrived;
  final double size;

  @override
  State<BearingArrow> createState() => _BearingArrowState();
}

class _BearingArrowState extends State<BearingArrow> {
  final _headingTracker = DeviceHeadingTracker();
  StreamSubscription<MagnetometerEvent>? _magSub;

  @override
  void initState() {
    super.initState();
    _magSub = magnetometerEventStream().listen((event) {
      if (mounted) {
        setState(() => _headingTracker.updateFromMagnetometer(event.x, event.y));
      }
    });
  }

  @override
  void dispose() {
    _magSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rotation = MissionNavigation.arrowRotationRadians(
      widget.targetBearing,
      _headingTracker.hasReading ? _headingTracker.heading : null,
    );
    final cardinal = MissionNavigation.cardinalLabel(widget.targetBearing);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.distanceLabel != null)
          Text(
            widget.distanceLabel!,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: widget.isArrived ? AppTheme.verified : AppTheme.primary,
            ),
          ),
        if (widget.isArrived) ...[
          const SizedBox(height: 4),
          const Text(
            'You\'ve arrived',
            style: TextStyle(color: AppTheme.verified, fontWeight: FontWeight.w600),
          ),
        ] else if (cardinal.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(cardinal, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceLight,
                  border: Border.all(color: AppTheme.glassBorder),
                ),
              ),
              if (rotation != null)
                Transform.rotate(
                  angle: rotation,
                  child: Icon(
                    Icons.navigation,
                    size: widget.size * 0.55,
                    color: widget.isArrived ? AppTheme.verified : AppTheme.primary,
                  ),
                )
              else
                Icon(Icons.explore_outlined, size: widget.size * 0.4, color: AppTheme.textSecondary),
              Positioned(
                top: 8,
                child: Text('N', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.7))),
              ),
            ],
          ),
        ),
        if (rotation == null && widget.targetBearing != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Hold phone flat for direction arrow',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Returns true when the app may read device location.
Future<bool> ensureMissionLocationPermission() async {
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.deniedForever) return false;
  return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
}

/// Live GPS + optional heading updates for mission screens.
mixin MissionGpsTracking<T extends StatefulWidget> on State<T> {
  Position? position;
  StreamSubscription<Position>? _positionSub;
  Timer? _breadcrumbTimer;
  final _headingTracker = DeviceHeadingTracker();

  /// When false, GPS updates refresh [position] without calling [setState] on the host.
  bool rebuildOnGpsUpdate = true;

  /// Request permission, fetch an immediate fix, then start the GPS stream.
  Future<void> bootMissionGps({
    required String ebId,
    required void Function(Position) onPosition,
    void Function(Position)? onBreadcrumb,
    Duration breadcrumbInterval = const Duration(seconds: 30),
    bool rebuildOnGpsUpdate = true,
  }) async {
    this.rebuildOnGpsUpdate = rebuildOnGpsUpdate;
    await ensureLocationPermission();
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        position = pos;
        onPosition(pos);
        if (this.rebuildOnGpsUpdate) setState(() {});
      }
    } catch (_) {}
    startMissionGps(
      ebId: ebId,
      onPosition: onPosition,
      onBreadcrumb: onBreadcrumb,
      breadcrumbInterval: breadcrumbInterval,
    );
  }

  void startMissionGps({
    required String ebId,
    required void Function(Position) onPosition,
    void Function(Position)? onBreadcrumb,
    Duration breadcrumbInterval = const Duration(seconds: 30),
  }) {
    _positionSub?.cancel();
    _breadcrumbTimer?.cancel();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((pos) {
      _headingTracker.updateFromPosition(pos);
      if (mounted) {
        position = pos;
        onPosition(pos);
        if (rebuildOnGpsUpdate) setState(() {});
      }
    });

    if (onBreadcrumb != null) {
      _breadcrumbTimer = Timer.periodic(breadcrumbInterval, (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition();
          onBreadcrumb(pos);
        } catch (_) {}
      });
    }
  }

  Future<void> ensureLocationPermission() async {
    await ensureMissionLocationPermission();
  }

  void stopMissionGps() {
    _positionSub?.cancel();
    _breadcrumbTimer?.cancel();
  }

  @override
  void dispose() {
    stopMissionGps();
    super.dispose();
  }
}
