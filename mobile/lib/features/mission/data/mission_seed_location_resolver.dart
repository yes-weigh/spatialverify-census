import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_geocoding_service.dart';
import 'hlo_pdf_metadata_parser.dart';

enum MissionSeedSource { pdfMetadata, userGps, fallback }

class MissionSeedLocation {
  const MissionSeedLocation({
    required this.lat,
    required this.lng,
    required this.source,
    this.metadata,
    this.geocodedAddress,
    this.geocodeQuery,
    this.userDistanceMeters,
    this.warning,
  });

  final double lat;
  final double lng;
  final MissionSeedSource source;
  final HloPdfMetadata? metadata;
  final String? geocodedAddress;
  final String? geocodeQuery;
  final double? userDistanceMeters;
  final String? warning;

  Map<String, dynamic> toAlignmentJson() => {
        'seedSource': source.name,
        if (metadata != null) 'pdfMetadata': metadata!.toJson(),
        if (geocodedAddress != null) 'geocodedAddress': geocodedAddress,
        if (geocodeQuery != null) 'geocodeQuery': geocodeQuery,
        if (userDistanceMeters != null) 'userDistanceMeters': userDistanceMeters!.round(),
        if (warning != null) 'warning': warning,
      };
}

/// Chooses where to place the CV boundary on the real map.
///
/// Prefers coordinates derived from the official PDF sidebar (district / ward / EB),
/// not the enumerator's current GPS — so importing at home does not shift the HLB
/// to the wrong neighborhood.
class MissionSeedLocationResolver {
  MissionSeedLocationResolver({GoogleGeocodingService? geocoding})
      : _geocoding = geocoding ?? GoogleGeocodingService();

  final GoogleGeocodingService _geocoding;

  Future<MissionSeedLocation> resolve({
    File? mapFile,
    HloPdfMetadata? metadata,
    required double userLat,
    required double userLng,
  }) async {
    final parsed = metadata ?? (mapFile != null ? await HloPdfMetadataParser.parseFile(mapFile) : null);

    if (parsed != null && AppConfig.hasGoogleMaps && _geocoding.isConfigured) {
      final geocoded = await _geocoding.geocodeFirstMatch(parsed.geocodeQueries());
      if (geocoded != null) {
        final distance = _distanceMeters(userLat, userLng, geocoded.location.latitude, geocoded.location.longitude);
        String? warning;
        if (distance > 2000) {
          warning =
              'HLB placed using official map address (${parsed.townVillage ?? parsed.subDistrict ?? parsed.district}). '
              'You are ${(distance / 1000).toStringAsFixed(1)} km away — use Adjust if the boundary looks wrong.';
        }
        return MissionSeedLocation(
          lat: geocoded.location.latitude,
          lng: geocoded.location.longitude,
          source: MissionSeedSource.pdfMetadata,
          metadata: parsed,
          geocodedAddress: geocoded.formattedAddress,
          geocodeQuery: geocoded.query,
          userDistanceMeters: distance,
          warning: warning,
        );
      }
    }

    if (parsed != null && !AppConfig.hasGoogleMaps) {
      return MissionSeedLocation(
        lat: userLat,
        lng: userLng,
        source: MissionSeedSource.userGps,
        metadata: parsed,
        warning:
            'Could not geocode PDF address without Google Maps API key. Boundary placed at your current location — use Adjust to move it to the correct HLB area.',
      );
    }

    return MissionSeedLocation(
      lat: userLat,
      lng: userLng,
      source: MissionSeedSource.userGps,
      metadata: parsed,
      warning: parsed == null
          ? 'Could not read location from PDF. Boundary placed at your current location — use Adjust if this is not your HLB area.'
          : 'Could not geocode PDF address. Boundary placed at your current location — use Adjust to move it to the correct HLB area.',
    );
  }

  static double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _degToRad(double deg) => deg * math.pi / 180;
}
