import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/layout_georef_models.dart';
import '../data/satellite_align_math.dart';

class LayoutGeorefApiService {
  LayoutGeorefApiService({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Future<LayoutGeorefSession> getSession(String ebId) async {
    final res = await _api.get('/layout-georef/eb/$ebId');
    return LayoutGeorefSession.fromJson(res.data as Map<String, dynamic>);
  }

  Future<LayoutGeorefSession> uploadLayout(
    String ebId, {
    required File file,
    File? preview,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.path.split(Platform.pathSeparator).last),
      if (preview != null)
        'preview': await MultipartFile.fromFile(preview.path, filename: 'preview.jpg'),
    });
    final res = await _api.post('/layout-georef/eb/$ebId/upload', data: form);
    return LayoutGeorefSession.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MissionIntelligencePackage> generateIntelligence(String ebId, double lat, double lng) async {
    final res = await _api.post('/layout-georef/eb/$ebId/generate-intelligence', data: {'lat': lat, 'lng': lng});
    return MissionIntelligencePackage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<({MissionIntelligencePackage intelligence, String? layoutImageUrl})> getIntelligence(String ebId) async {
    final res = await _api.get('/layout-georef/eb/$ebId/intelligence');
    final data = res.data as Map<String, dynamic>;
    return (
      intelligence: MissionIntelligencePackage.fromJson(data['intelligence'] as Map<String, dynamic>),
      layoutImageUrl: data['layoutImageUrl'] as String?,
    );
  }

  Future<void> saveImageBounds(String ebId, ImageBounds bounds) async {
    await _api.put('/layout-georef/eb/$ebId/image-bounds', data: {'bounds': bounds.toJson()});
  }

  Future<void> saveGpsBoundary(String ebId, List<GpsPoint> boundary) async {
    await _api.put('/layout-georef/eb/$ebId/gps-boundary', data: {
      'boundary': boundary.map((p) => p.toJson()).toList(),
    });
  }

  Future<void> confirmIntelligence(String ebId) async {
    await _api.post('/layout-georef/eb/$ebId/confirm-intelligence');
  }

  Future<GeorefValidation> validate(String ebId) async {
    final res = await _api.get('/layout-georef/eb/$ebId/validate');
    return GeorefValidation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> finalize(String ebId) async {
    await _api.post('/layout-georef/eb/$ebId/finalize');
  }
}
