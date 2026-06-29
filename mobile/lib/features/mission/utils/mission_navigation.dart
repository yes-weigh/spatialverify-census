import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import '../models/mission_models.dart';

/// Field navigation helpers — distance + bearing for building guidance.
class MissionNavigation {
  MissionNavigation._();

  static const double arrivalThresholdMeters = 30;

  static double? distanceMeters(Position? from, MissionBuilding? to) {
    if (from == null || to == null) return null;
    if (to.latitude == null || to.longitude == null) return null;
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude!,
      to.longitude!,
    );
  }

  static String? distanceLabel(Position? from, MissionBuilding? to) {
    final meters = distanceMeters(from, to);
    if (meters == null) return null;
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  /// Geographic bearing from current position to target (0° = north, clockwise).
  static double? bearingDegrees(Position? from, MissionBuilding? to) {
    if (from == null || to == null) return null;
    if (to.latitude == null || to.longitude == null) return null;
    return Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      to.latitude!,
      to.longitude!,
    );
  }

  static bool hasGpsPin(MissionBuilding building) =>
      building.latitude != null && building.longitude != null;

  static bool isArrived(Position? from, MissionBuilding? to) {
    final meters = distanceMeters(from, to);
    if (meters == null) return false;
    return meters <= arrivalThresholdMeters;
  }

  static double? distanceMetersToLatLng(Position? from, double? lat, double? lng) {
    if (from == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(from.latitude, from.longitude, lat, lng);
  }

  static String? distanceLabelToLatLng(Position? from, double? lat, double? lng) {
    final meters = distanceMetersToLatLng(from, lat, lng);
    if (meters == null) return null;
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  static double? bearingToLatLng(Position? from, double? lat, double? lng) {
    if (from == null || lat == null || lng == null) return null;
    return Geolocator.bearingBetween(from.latitude, from.longitude, lat, lng);
  }

  static bool isArrivedAtLatLng(Position? from, double? lat, double? lng) {
    final meters = distanceMetersToLatLng(from, lat, lng);
    if (meters == null) return false;
    return meters <= arrivalThresholdMeters;
  }

  /// Arrow rotation in radians: relative to device heading (0 = points ahead).
  static double? arrowRotationRadians(double? targetBearing, double? deviceHeading) {
    if (targetBearing == null || deviceHeading == null) return null;
    var delta = targetBearing - deviceHeading;
    while (delta > 180) delta -= 360;
    while (delta < -180) delta += 360;
    return delta * math.pi / 180;
  }

  static String cardinalLabel(double? bearing) {
    if (bearing == null) return '';
    final normalized = (bearing + 360) % 360;
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((normalized + 22.5) / 45).floor() % 8;
    return labels[index];
  }
}

/// Tracks device compass heading via magnetometer (phone held flat).
class DeviceHeadingTracker {
  DeviceHeadingTracker();

  double _heading = 0;
  bool _hasReading = false;

  double get heading => _heading;
  bool get hasReading => _hasReading;

  void updateFromMagnetometer(double x, double y) {
    _heading = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    _hasReading = true;
  }

  void updateFromPosition(Position position) {
    if (position.heading >= 0 && (position.speed >= 0.5 || position.speedAccuracy >= 0)) {
      _heading = position.heading;
      _hasReading = true;
    }
  }
}

class ActiveMission {
  const ActiveMission({
    required this.projectId,
    required this.ebId,
    required this.ebCode,
    required this.phase,
  });

  final String projectId;
  final String ebId;
  final String ebCode;
  /// `mapping` = HLB draft creation, `listing` = house listing walk
  final String phase;
}
