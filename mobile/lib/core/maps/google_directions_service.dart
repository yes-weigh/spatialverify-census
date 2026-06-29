import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_config.dart';
import 'polyline_decoder.dart';

enum NavigationTravelMode { bicycling, walking, driving }

class DirectionsStep {
  const DirectionsStep({
    required this.instruction,
    required this.distanceText,
    required this.durationText,
    required this.endLocation,
  });

  final String instruction;
  final String distanceText;
  final String durationText;
  final LatLng endLocation;
}

class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    required this.travelMode,
  });

  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final int distanceMeters;
  final int durationSeconds;
  final List<DirectionsStep> steps;
  final NavigationTravelMode travelMode;
}

class GoogleDirectionsService {
  GoogleDirectionsService({Dio? dio, String? apiKey})
      : _dio = dio ?? Dio(),
        _apiKey = apiKey ?? AppConfig.googleMapsApiKey;

  final Dio _dio;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<DirectionsRoute?> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    NavigationTravelMode mode = NavigationTravelMode.bicycling,
  }) async {
    if (!isConfigured) return null;

    for (final attempt in [mode, NavigationTravelMode.walking]) {
      final route = await _requestRoute(origin: origin, destination: destination, mode: attempt);
      if (route != null) return route;
    }
    return null;
  }

  Future<DirectionsRoute?> _requestRoute({
    required LatLng origin,
    required LatLng destination,
    required NavigationTravelMode mode,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': mode.name,
          'key': _apiKey,
        },
      );

      final data = res.data;
      if (data?['status'] != 'OK') return null;

      final routes = data!['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>?;
      if (legs == null || legs.isEmpty) return null;

      final leg = legs.first as Map<String, dynamic>;
      final overview = route['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overview?['points'] as String?;
      if (encoded == null) return null;

      final distance = leg['distance'] as Map<String, dynamic>?;
      final duration = leg['duration'] as Map<String, dynamic>?;

      final steps = <DirectionsStep>[];
      for (final raw in leg['steps'] as List<dynamic>? ?? []) {
        final step = raw as Map<String, dynamic>;
        final end = step['end_location'] as Map<String, dynamic>?;
        if (end == null) continue;
        steps.add(DirectionsStep(
          instruction: _stripHtml(step['html_instructions'] as String? ?? 'Continue'),
          distanceText: (step['distance'] as Map?)?['text'] as String? ?? '',
          durationText: (step['duration'] as Map?)?['text'] as String? ?? '',
          endLocation: LatLng(
            (end['lat'] as num).toDouble(),
            (end['lng'] as num).toDouble(),
          ),
        ),);
      }

      return DirectionsRoute(
        points: decodeGooglePolyline(encoded),
        distanceText: distance?['text'] as String? ?? '',
        durationText: duration?['text'] as String? ?? '',
        distanceMeters: (distance?['value'] as num?)?.toInt() ?? 0,
        durationSeconds: (duration?['value'] as num?)?.toInt() ?? 0,
        steps: steps,
        travelMode: mode,
      );
    } catch (_) {
      return null;
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
