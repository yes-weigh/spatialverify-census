import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

/// Last non-OK Places API status — useful when all searches return empty.
String? lastPlacesApiStatus;

bool get placesApiAccessDenied => lastPlacesApiStatus == 'REQUEST_DENIED';

void resetPlacesApiStatus() => lastPlacesApiStatus = null;

/// Google Places search — mirrors what users type in Google Maps.
class GooglePlacesService {
  GooglePlacesService({Dio? dio, String? apiKey})
      : _dio = dio ?? Dio(),
        _apiKey = apiKey ?? AppConfig.googleMapsApiKey;

  final Dio _dio;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Try several queries; unbiased search first (like the Maps app).
  Future<List<PlaceMatchResult>> searchBestMatch({
    required Iterable<String> queries,
    LatLng? bias,
    int maxResults = 5,
  }) async {
    final seen = <String>{};
    final merged = <PlaceMatchResult>[];

    for (final query in queries) {
      if (query.trim().length < 3) continue;
      if (placesApiAccessDenied) break;

      // Unbiased first — matches typing in Google Maps without GPS bias.
      for (final result in await _findPlaceFromText(query)) {
        if (seen.add(result.placeId)) merged.add(result);
      }
      if (merged.isNotEmpty || placesApiAccessDenied) break;

      for (final result in await search(query: query)) {
        if (seen.add(result.placeId)) merged.add(result);
      }
      if (merged.isNotEmpty || placesApiAccessDenied) break;

      if (bias != null) {
        for (final result in await _findPlaceFromText(query, bias: bias)) {
          if (seen.add(result.placeId)) merged.add(result);
        }
        if (merged.isNotEmpty || placesApiAccessDenied) break;

        for (final result in await search(query: query, bias: bias, useLocationBias: true)) {
          if (seen.add(result.placeId)) merged.add(result);
        }
        if (merged.isNotEmpty || placesApiAccessDenied) break;
      }
    }

    return merged.take(maxResults).toList();
  }

  Future<List<PlaceMatchResult>> search({
    required String query,
    LatLng? bias,
    bool useLocationBias = false,
    int radiusMeters = 80000,
    int maxResults = 5,
  }) async {
    if (!isConfigured || query.trim().length < 3) return [];

    try {
      final params = <String, dynamic>{
        'query': query,
        'region': 'in',
        'key': _apiKey,
      };
      if (useLocationBias && bias != null) {
        params['location'] = '${bias.latitude},${bias.longitude}';
        params['radius'] = radiusMeters;
      }

      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
        queryParameters: params,
      );

      final data = res.data;
      final status = data?['status'] as String?;
      _recordStatus(status, 'textsearch', query);
      if (status != 'OK' && status != 'ZERO_RESULTS') return [];

      final results = data!['results'] as List<dynamic>? ?? [];
      return [
        for (final raw in results.take(maxResults))
          if (raw is Map<String, dynamic>) _parseResult(raw),
      ].whereType<PlaceMatchResult>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PlaceMatchResult>> _findPlaceFromText(
    String input, {
    LatLng? bias,
  }) async {
    if (!isConfigured || input.trim().length < 3) return [];

    try {
      final params = <String, dynamic>{
        'input': input,
        'inputtype': 'textquery',
        'fields': 'place_id,name,formatted_address,geometry',
        'region': 'in',
        'key': _apiKey,
      };
      if (bias != null) {
        params['locationbias'] = 'circle:80000@${bias.latitude},${bias.longitude}';
      }

      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/findplacefromtext/json',
        queryParameters: params,
      );

      final data = res.data;
      final status = data?['status'] as String?;
      _recordStatus(status, 'findplace', input);
      if (status != 'OK') return [];

      final candidates = data!['candidates'] as List<dynamic>? ?? [];
      return [
        for (final raw in candidates.take(3))
          if (raw is Map<String, dynamic>) _parseResult(raw),
      ].whereType<PlaceMatchResult>().toList();
    } catch (_) {
      return [];
    }
  }

  void _recordStatus(String? status, String api, String query) {
    if (status == null || status == 'OK' || status == 'ZERO_RESULTS') return;
    lastPlacesApiStatus = status;
    if (kDebugMode) {
      debugPrint('Places $api status=$status query="$query"');
    }
  }

  /// Type-ahead suggestions (same as Google Maps search box).
  Future<List<PlaceAutocompletePrediction>> autocomplete({
    required String input,
    LatLng? bias,
    int radiusMeters = 50000,
  }) async {
    if (!isConfigured || input.trim().length < 2) return [];

    try {
      final params = <String, dynamic>{
        'input': input,
        'types': 'establishment|geocode',
        'components': 'country:in',
        'key': _apiKey,
      };
      if (bias != null) {
        params['location'] = '${bias.latitude},${bias.longitude}';
        params['radius'] = radiusMeters;
      }

      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: params,
      );

      final data = res.data;
      final status = data?['status'] as String?;
      _recordStatus(status, 'autocomplete', input);
      if (status != 'OK' && status != 'ZERO_RESULTS') return [];

      final predictions = data?['predictions'] as List<dynamic>? ?? [];
      return [
        for (final raw in predictions.take(8))
          if (raw is Map<String, dynamic>)
            PlaceAutocompletePrediction(
              placeId: raw['place_id'] as String? ?? '',
              description: raw['description'] as String? ?? '',
            ),
      ].where((p) => p.placeId.isNotEmpty && p.description.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Resolve a prediction to coordinates for georeferencing.
  Future<PlaceMatchResult?> fetchPlaceDetails(String placeId) async {
    if (!isConfigured || placeId.isEmpty) return null;

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'place_id,name,formatted_address,geometry',
          'key': _apiKey,
        },
      );

      final data = res.data;
      final status = data?['status'] as String?;
      _recordStatus(status, 'details', placeId);
      if (status != 'OK') return null;

      final result = data?['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      return _parseResult(result);
    } catch (_) {
      return null;
    }
  }

  PlaceMatchResult? _parseResult(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final name = json['name'] as String? ?? '';
    if (name.isEmpty) return null;

    return PlaceMatchResult(
      placeId: json['place_id'] as String? ?? '',
      name: name,
      address: json['formatted_address'] as String? ?? '',
      location: LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      ),
    );
  }
}

class PlaceAutocompletePrediction {
  const PlaceAutocompletePrediction({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

class PlaceMatchResult {
  const PlaceMatchResult({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
  });

  final String placeId;
  final String name;
  final String address;
  final LatLng location;
}
