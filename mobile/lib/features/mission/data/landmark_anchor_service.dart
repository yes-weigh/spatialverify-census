import 'dart:io';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/maps/google_geocoding_service.dart';
import '../../../core/maps/google_places_service.dart';
import '../models/landmark_anchor_models.dart';
import 'hlo_pdf_metadata_parser.dart';
import 'map_panel_ocr_service.dart';
import 'mission_seed_location_resolver.dart';

/// OCR map labels → Google Places search → rows for user verification.
class LandmarkAnchorService {
  LandmarkAnchorService({
    MapPanelOcrService? ocr,
    GooglePlacesService? places,
    GoogleGeocodingService? geocoding,
    MissionSeedLocationResolver? seedResolver,
  })  : _ocr = ocr ?? MapPanelOcrService(),
        _places = places ?? GooglePlacesService(),
        _geocoding = geocoding ?? GoogleGeocodingService(),
        _seedResolver = seedResolver ?? MissionSeedLocationResolver();

  final MapPanelOcrService _ocr;
  final GooglePlacesService _places;
  final GoogleGeocodingService _geocoding;
  final MissionSeedLocationResolver _seedResolver;

  static const minLabelsForVerification = 2;
  static const maxLabelsToSearch = 8;
  static const _maxMatchDistanceM = 12000.0;
  static const _distance = Distance();

  Future<LandmarkAnchorPrepResult> prepare({
    required List<int> mapBytes,
    required String mapFilePath,
    required double userLat,
    required double userLng,
  }) async {
    final bytes = mapBytes is Uint8List ? mapBytes : Uint8List.fromList(mapBytes);
    final seed = await _seedResolver.resolve(
      mapFile: File(mapFilePath),
      userLat: userLat,
      userLng: userLng,
    );

    final labels = await _ocr.extractLabels(bytes);
    final metadata = await HloPdfMetadataParser.parseFile(File(mapFilePath));
    final locality = metadata?.townVillage ?? metadata?.subDistrict ?? metadata?.district ?? 'Kerala';
    final district = metadata?.district;

    if (!AppConfig.hasGoogleMaps || !_places.isConfigured) {
      return LandmarkAnchorPrepResult(
        seed: seed,
        rows: [
          for (final label in labels.take(maxLabelsToSearch))
            LandmarkMatchRow(label: label, suggestions: const []),
        ],
        ocrLabelCount: labels.length,
        searchLocality: locality,
        searchDistrict: district,
      );
    }

    final rows = <LandmarkMatchRow>[
      for (final label in labels.take(maxLabelsToSearch))
        LandmarkMatchRow(label: label, suggestions: const []),
    ];

    return LandmarkAnchorPrepResult(
      seed: seed,
      rows: rows,
      ocrLabelCount: labels.length,
      searchLocality: locality,
      searchDistrict: district,
    );
  }

  /// Builds Maps-style queries — exact OCR text first, not "Kochi Kerala …" prefix.
  static List<String> buildPlaceQueries({
    required String labelText,
    String? pdfLocality,
    String? district,
  }) {
    final text = labelText.trim();
    final queries = <String>[];

    // PDF town first — keeps matches in Aluva/NAD Puram, not Kochi city centre.
    if (pdfLocality != null && pdfLocality.length > 2) {
      queries.addAll([
        '$text $pdfLocality Kerala India',
        '$text $pdfLocality Kerala',
      ]);
    }
    if (district != null && district.length > 2) {
      queries.add('$text $district Kerala India');
    }

    queries.addAll([
      text,
      '$text Kerala India',
      '$text Kerala',
    ]);

    if (text.contains(',')) {
      final parts = text.split(',').map((s) => s.trim()).where((s) => s.length >= 2).toList();
      if (parts.length >= 2) {
        final feature = parts.first;
        final place = parts.last;
        queries.addAll([
          '$feature $place Kerala India',
          '$place $feature Kerala',
          '$place Kerala India',
          '$feature near $place Kerala',
        ]);
      }
    }

    final lower = text.toLowerCase();
    if (pdfLocality != null &&
        pdfLocality.length > 2 &&
        !lower.contains(pdfLocality.toLowerCase())) {
      queries.add('$text $pdfLocality Kerala');
    }
    if (district != null &&
        district.length > 2 &&
        !lower.contains(district.toLowerCase())) {
      queries.add('$text $district Kerala India');
    }

    return queries.map((q) => q.replaceAll(RegExp(r'\s+'), ' ').trim()).toSet().toList();
  }

  Future<List<PlaceMatchCandidate>> searchPlacesForLabel({
    required String labelText,
    required String locality,
    required MissionSeedLocation seed,
    String? district,
  }) async {
    if (!AppConfig.hasGoogleMaps || !_places.isConfigured || labelText.trim().length < 3) {
      return const [];
    }

    final queries = buildPlaceQueries(
      labelText: labelText,
      pdfLocality: locality,
      district: district,
    );
    final bias = LatLng(seed.lat, seed.lng);

    if (!placesApiAccessDenied) {
      final results = await _places.searchBestMatch(queries: queries, bias: bias);
      if (results.isNotEmpty) {
        return _rankMatches(
          [
            for (final r in results)
              PlaceMatchCandidate(
                placeId: r.placeId,
                name: r.name,
                address: r.address,
                location: r.location,
              ),
          ],
          bias,
        );
      }
    }

    // Geocoding fallback — often resolves "Church, NAD Puram" when Places is denied or empty.
    if (_geocoding.isConfigured && !geocodingApiAccessDenied) {
      final geoCandidates = <PlaceMatchCandidate>[];
      for (final query in queries.take(6)) {
        if (geocodingApiAccessDenied) break;
        final geo = await _geocoding.geocode(query);
        if (geo == null) continue;
        geoCandidates.add(
          PlaceMatchCandidate(
            placeId: 'geocode:${geo.query.hashCode}',
            name: _nameFromGeocode(geo.formattedAddress, labelText),
            address: geo.formattedAddress,
            location: geo.location,
          ),
        );
      }
      if (geoCandidates.isNotEmpty) {
        return _rankMatches(geoCandidates, bias);
      }
    }

    return const [];
  }

  /// Prefer matches near the PDF sidebar geocode (Aluva), not random Kerala hits.
  List<PlaceMatchCandidate> _rankMatches(List<PlaceMatchCandidate> matches, LatLng seed) {
    if (matches.isEmpty) return matches;
    final near = matches.where((m) => _distance(seed, m.location) <= _maxMatchDistanceM).toList();
    final pool = near.isNotEmpty ? near : matches;
    pool.sort((a, b) => _distance(seed, a.location).compareTo(_distance(seed, b.location)));
    return pool.take(5).toList();
  }

  static int qualityPercentFromRms(double rmsMeters) {
    if (rmsMeters < 10) return 92;
    if (rmsMeters < 25) return 78;
    if (rmsMeters < 50) return 55;
    return 35;
  }

  static String _nameFromGeocode(String formattedAddress, String fallback) {
    final first = formattedAddress.split(',').first.trim();
    if (first.length >= 3) return first;
    return fallback.trim();
  }

  Future<void> dispose() => _ocr.dispose();
}

class LandmarkAnchorPrepResult {
  const LandmarkAnchorPrepResult({
    required this.seed,
    required this.rows,
    required this.ocrLabelCount,
    required this.searchLocality,
    this.searchDistrict,
  });

  final MissionSeedLocation seed;
  final List<LandmarkMatchRow> rows;
  final int ocrLabelCount;
  final String searchLocality;
  final String? searchDistrict;

  bool get shouldVerify => ocrLabelCount >= LandmarkAnchorService.minLabelsForVerification;
}
