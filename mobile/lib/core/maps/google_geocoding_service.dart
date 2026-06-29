import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

/// Last non-OK Geocoding API status.
String? lastGeocodingApiStatus;

bool get geocodingApiAccessDenied => lastGeocodingApiStatus == 'REQUEST_DENIED';

void resetGeocodingApiStatus() => lastGeocodingApiStatus = null;

class GeocodingResult {
  const GeocodingResult({
    required this.location,
    required this.formattedAddress,
    required this.query,
  });

  final LatLng location;
  final String formattedAddress;
  final String query;
}

/// Resolves administrative place names to coordinates via Google Geocoding API.
class GoogleGeocodingService {
  GoogleGeocodingService({Dio? dio, String? apiKey})
      : _dio = dio ?? Dio(),
        _apiKey = apiKey ?? AppConfig.googleMapsApiKey;

  final Dio _dio;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<GeocodingResult?> geocode(String query) async {
    if (!isConfigured || query.trim().isEmpty) return null;

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'address': query,
          'region': 'in',
          'components': 'country:IN|administrative_area:Kerala',
          'key': _apiKey,
        },
      );

      final data = res.data;
      final status = data?['status'] as String?;
      if (status != 'OK') {
        if (status != null && status != 'ZERO_RESULTS') {
          lastGeocodingApiStatus = status;
          if (kDebugMode) {
            debugPrint('Geocoding status=$status query="$query"');
          }
        }
        return null;
      }

      final results = data!['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      return GeocodingResult(
        location: LatLng(
          (location['lat'] as num).toDouble(),
          (location['lng'] as num).toDouble(),
        ),
        formattedAddress: first['formatted_address'] as String? ?? query,
        query: query,
      );
    } catch (_) {
      return null;
    }
  }

  Future<GeocodingResult?> geocodeFirstMatch(Iterable<String> queries) async {
    for (final query in queries) {
      final result = await geocode(query);
      if (result != null) return result;
    }
    return null;
  }
}
