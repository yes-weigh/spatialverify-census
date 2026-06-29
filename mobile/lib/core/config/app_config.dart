import '../brand/app_brand.dart';

class AppConfig {
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  /// Maps SDK (Android/iOS manifest) + Directions API (in-app routing).
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static bool get hasGoogleMaps => googleMapsApiKey.isNotEmpty;

  static const bool useLocalImport = true;

  static const String appName = AppBrand.name;
  static const int syncBatchSize = 50;
  static const int syncRetryMax = 5;
  static const double minDetectionConfidence = 0.5;
  static const double geofenceCheckIntervalMs = 5000;
  static const double locationUpdateIntervalMs = 2000;
}
