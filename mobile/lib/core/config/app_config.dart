class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:3000/ws',
  );

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

  /// When true, no census backend — all mission data on device (+ Google Maps API only).
  static const bool standaloneMode = bool.fromEnvironment(
    'STANDALONE_MODE',
    defaultValue: false,
  );

  /// Cloud sync via Firebase Auth + Firestore + Storage (multi-device field work).
  static const bool useFirebase = bool.fromEnvironment(
    'USE_FIREBASE',
    defaultValue: true,
  );

  /// Legacy REST API mode when Firebase is off and standalone is off.
  static bool get useRestBackend => !standaloneMode && !useFirebase;

  static const String appName = 'SpatialVerify';
  static const int syncBatchSize = 50;
  static const int syncRetryMax = 5;
  static const double minDetectionConfidence = 0.5;
  static const double geofenceCheckIntervalMs = 5000;
  static const double locationUpdateIntervalMs = 2000;
}
