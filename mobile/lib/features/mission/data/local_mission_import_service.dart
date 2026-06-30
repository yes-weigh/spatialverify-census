import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/storage/mission_layout_storage.dart';

import '../../../core/utils/json_map_utils.dart';
import '../../../core/pdf/hlo_pdf_renderer.dart';
import '../../../core/spatial_cv/spatial_cv_image.dart';
import '../../../core/spatial_cv/spatial_cv_pipeline.dart';
import '../../../core/spatial_cv/spatial_cv_types.dart';
import '../models/landmark_anchor_models.dart';
import '../models/layout_georef_models.dart';
import '../models/manual_upload_draft.dart';
import '../models/pdf_georef_models.dart';
import 'hlb_local_cache.dart';
import 'hlb_local_state.dart';
import 'hlo_pdf_metadata_parser.dart';
import 'landmark_anchor_service.dart';
import 'layout_georef_math.dart';
import 'mission_map_session.dart';
import 'map_panel_ocr_service.dart';
import 'mission_cv_worker.dart';
import 'mission_seed_location_resolver.dart';
import 'hlo_layout_sheet_measure.dart';
import '../models/hlo_layout_sheet_insets.dart';
import '../models/hlo_map_panel_rect.dart';
import 'satellite_align_math.dart';

/// Cached CV + OCR/Places prep between upload and landmark verification.
class MissionImportDraft {
  MissionImportDraft({
    required this.mapBytes,
    required this.layoutPath,
    required this.cv,
    required this.uvRing,
    required this.anchorPrep,
  });

  final Uint8List mapBytes;
  final String layoutPath;
  final CvExtractionResult cv;
  final List<({double x, double y})> uvRing;
  final LandmarkAnchorPrepResult anchorPrep;
}

/// Full on-device HLO import — PDF/image → CV → landmark anchors → GPS alignment.
class LocalMissionImportService {
  LocalMissionImportService({required HlbLocalCache cache}) : _cache = cache;

  final HlbLocalCache _cache;

  Future<MissionImportDraft> prepareImport({
    required String ebId,
    required File mapFile,
    required double userLat,
    required double userLng,
    LandmarkAnchorService? anchorService,
  }) async {
    final bytes = await _loadMapBytes(mapFile);
    final layoutPath = await saveMissionLayoutBytes(ebId, bytes);

    UvPoint? blockCenterUv;
    final metadata = await HloPdfMetadataParser.parseFile(mapFile);
    if (metadata?.ebNo != null) {
      final ocr = MapPanelOcrService();
      try {
        final center = await ocr.findEbBlockCenter(bytes, metadata!.ebNo!);
        if (center != null) blockCenterUv = UvPoint(center.x, center.y);
      } finally {
        await ocr.dispose();
      }
    }

    final cv = runSpatialCvPipeline(bytes, blockCenterUv: blockCenterUv);

    if (cv.boundaryPolygon.length < 3) {
      throw Exception('Could not detect HLB boundary on officer map — use Adjust to mark manually');
    }

    final uvRing = cv.boundaryPolygon.map((p) => (x: p.x, y: p.y)).toList();
    final anchor = await (anchorService ?? LandmarkAnchorService()).prepare(
      mapBytes: bytes,
      mapFilePath: mapFile.path,
      userLat: userLat,
      userLng: userLng,
    );

    return MissionImportDraft(
      mapBytes: bytes,
      layoutPath: layoutPath,
      cv: cv,
      uvRing: uvRing,
      anchorPrep: anchor,
    );
  }

  Future<MissionIntelligencePackage> buildIntelligence({
    required MissionImportDraft draft,
    MissionSeedLocation? seedLocation,
    List<GeorefControlPoint>? controlPoints,
  }) async {
    final cv = draft.cv;
    final uvRing = draft.uvRing;

    late ImageBounds imageBounds;
    late List<GpsPoint> gpsBoundary;
    late Map<String, dynamic> alignmentBlock;
    List<double>? affineMatrix;

    if (controlPoints != null && controlPoints.length >= kMinGeorefMatchedPins) {
      _validateControlPoints(controlPoints);
      final aligned = SatelliteAlignMath.alignFromControlPoints(controlPoints, uvRing);
      imageBounds = aligned.imageBounds;
      gpsBoundary = aligned.gpsBoundary;
      affineMatrix = aligned.affineMatrix;
      alignmentBlock = {
        'autoAligned': true,
        'method': 'landmark_control_points',
        'qualityPercent': LandmarkAnchorService.qualityPercentFromRms(aligned.rmsErrorMeters),
        'score': aligned.alignmentLabel.toLowerCase().replaceAll(' ', '_'),
        'imageBounds': imageBounds.toJson(),
        'affineMatrix': aligned.affineMatrix,
        'rmsErrorMeters': aligned.rmsErrorMeters.round(),
        'alignmentLabel': aligned.alignmentLabel,
        'controlPoints': controlPoints.map((p) => p.toJson()).toList(),
      };
    } else {
      final seed = seedLocation ?? draft.anchorPrep.seed;
      final aligned = SatelliteAlignMath.autoAlignFromBoundary(uvRing, seed.lat, seed.lng);
      imageBounds = aligned.imageBounds;
      gpsBoundary = aligned.gpsBoundary;
      alignmentBlock = {
        'autoAligned': true,
        'method': 'seed_auto',
        'qualityPercent': ((cv.confidence.overall * 100).round()).clamp(0, 100),
        'score': cv.confidence.overall >= 0.85 ? 'excellent' : cv.confidence.overall >= 0.65 ? 'good' : 'needs_review',
        'imageBounds': imageBounds.toJson(),
        'seedLat': seed.lat,
        'seedLng': seed.lng,
        ...seed.toAlignmentJson(),
      };
    }

    LatLng toGps(double u, double v) {
      if (affineMatrix != null) return LayoutGeorefMath.applyAffine(affineMatrix, u, v);
      return SatelliteAlignMath.imageUvToLatLng(u, v, imageBounds);
    }

    final observationTargets = cv.observationTargets.map((s) {
      final gps = toGps(s.sketchX, s.sketchY);
      return {
        ...s.toJson(),
        'label': 'Observation target',
        'lat': gps.latitude,
        'lng': gps.longitude,
      };
    }).toList();

    final intelligenceJson = {
      'generatedAt': DateTime.now().toIso8601String(),
      'engine': 'spatial_cv',
      'engineVersion': spatialCvVersion,
      'alignment': alignmentBlock,
      'confidence': cv.confidence.toJson(),
      'boundary': {
        'source': 'cv_detected',
        'confidence': cv.confidence.boundary,
        'gpsRing': gpsBoundary.map((p) => p.toJson()).toList(),
        'uvRing': uvRing.map((p) => {'x': p.x, 'y': p.y}).toList(),
      },
      'hypotheses': {
        'observationTargets': observationTargets,
        'roads': cv.roadSegments,
        'landmarks': cv.landmarks.map((l) => l.toJson()).toList(),
        'waterBodies': cv.waterBodies,
        'canalCrossings': cv.canalCrossings,
        'vegetationPatches': cv.vegetationPatches,
      },
      'summary': {
        'observationTargets': observationTargets.length,
        'roadSegments': cv.roadSegments.length,
        'possibleLandmarks': cv.landmarks.length,
        'canalCrossings': cv.canalCrossings.length,
        'vegetationPatches': cv.vegetationPatches.length,
      },
      'layoutImagePath': draft.layoutPath,
    };

    return MissionIntelligencePackage.fromJson(intelligenceJson);
  }

  List<GeorefControlPoint> controlPointsFromMatches(List<LandmarkMatchRow> rows) {
    return [
      for (final row in rows.where((r) => r.isReady))
        GeorefControlPoint(
          id: row.label.id,
          label: row.label.text,
          sketchX: row.label.uvX,
          sketchY: row.label.uvY,
          lat: row.selected!.location.latitude,
          lng: row.selected!.location.longitude,
        ),
    ];
  }

  List<GeorefControlPoint> controlPointsFromPins(List<PdfGeorefPin> pins) {
    return [
      for (final pin in pins.where((p) => p.isReady))
        GeorefControlPoint(
          id: 'pin_${pin.number}',
          label: 'Pin ${pin.number}',
          sketchX: pin.uvX,
          sketchY: pin.uvY,
          lat: pin.place!.location.latitude,
          lng: pin.place!.location.longitude,
        ),
    ];
  }

  List<PdfGeorefPin> pinsFromControlPoints(List<GeorefControlPoint> points) {
    return [
      for (var i = 0; i < points.length; i++)
        PdfGeorefPin(
          number: i + 1,
          uvX: points[i].sketchX,
          uvY: points[i].sketchY,
          searchText: points[i].label,
          place: PlaceMatchCandidate(
            placeId: points[i].id,
            name: points[i].label,
            address: points[i].label,
            location: LatLng(points[i].lat, points[i].lng),
          ),
        ),
    ];
  }

  /// Restore saved layout + boundary + pins so the user can redo 3-pin alignment.
  Future<AlignmentRestartSession?> loadAlignmentRestart(String ebId) async {
    final session = await loadReorientSession(ebId);
    if (session == null) return null;

    final bytes = await readMissionLayoutBytes(session.layoutImagePath);
    if (bytes == null || bytes.isEmpty) return null;

    final raw = session.intelligence.raw ?? {};
    final boundary = raw['boundary'] as Map<String, dynamic>? ?? {};
    final uvRing = <({double x, double y})>[
      for (final p in boundary['uvRing'] as List<dynamic>? ?? [])
        if (p is Map)
          (
            x: ((p['x'] ?? p['u']) as num).toDouble(),
            y: ((p['y'] ?? p['v']) as num).toDouble(),
          ),
    ];
    if (uvRing.length < 3) return null;

    final alignment = raw['alignment'] as Map<String, dynamic>? ?? {};
    final controlPoints = (alignment['controlPoints'] as List<dynamic>? ?? [])
        .map((e) => GeorefControlPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final gps = session.intelligence.gpsBoundary;
    var lat = 20.5937;
    var lng = 78.9629;
    if (gps.isNotEmpty) {
      lat = gps.map((p) => p.lat).reduce((a, b) => a + b) / gps.length;
      lng = gps.map((p) => p.lng).reduce((a, b) => a + b) / gps.length;
    }

    return AlignmentRestartSession(
      layoutImagePath: session.layoutImagePath,
      mapBytes: bytes,
      uvRing: uvRing,
      pins: pinsFromControlPoints(controlPoints),
      seed: MissionSeedLocation(
        lat: lat,
        lng: lng,
        source: MissionSeedSource.pdfMetadata,
        warning: 'Update your 3 pins, then continue to satellite preview.',
      ),
    );
  }

  /// Clears boundary/overlay from a prior import before replacing [layout.png].
  Future<void> beginReimport(String ebId) async {
    final state = await _cache.get(ebId);
    if (state == null) return;

    final lg = state.layoutGeoref != null
        ? Map<String, dynamic>.from(state.layoutGeoref!)
        : <String, dynamic>{};
    for (final key in [
      'gpsBoundary',
      'boundaryPolygon',
      'polygonAreaSqMeters',
      'imageBounds',
      'uvRing',
      'missionIntelligence',
      'status',
      'finalizedAt',
      'sourcePageSizePt',
      'sourceLayoutInsets',
      'sourceMapPanelRect',
      'sourceFullSheetPath',
    ]) {
      lg.remove(key);
    }

    await _cache.put(state.copyWith(
      clearOfficialBoundary: true,
      clearMissionIntelligence: true,
      layoutGeoref: lg.isEmpty ? null : lg,
    ));
  }

  /// Rasterize PDF/image only — show map immediately for manual georef.
  Future<ManualUploadDraft> prepareManualUpload({
    required String ebId,
    File? mapFile,
    Uint8List? mapBytes,
    String? mapFileName,
    required double userLat,
    required double userLng,
  }) async {
    await beginReimport(ebId);
    await Future<void>.delayed(Duration.zero);
    final source = await _readMapSource(mapFile: mapFile, mapBytes: mapBytes, mapFileName: mapFileName);
    final isPdf = source.name.toLowerCase().endsWith('.pdf');
    final fullPageBytes = isPdf ? await renderHloPdfPagePng(source.bytes) : source.bytes;
    final pageSize = isPdf ? await readHloPdfPageSizePt(source.bytes) : null;
    final sheetInsets = measureHloLayoutSheetInsets(fullPageBytes);
    final mapPanelRect = measureMapPanelRect(fullPageBytes);
    final fullSheetPath = await saveMissionFullSheetBytes(ebId, fullPageBytes);
    final rendered = prepareLayoutMapImageBytes(fullPageBytes);
    final layoutPath = await saveMissionLayoutBytes(ebId, rendered);
    if (pageSize != null) {
      await saveSourcePageSize(ebId, pageSize);
    }
    await saveSourceLayoutInsets(ebId, sheetInsets);
    await saveSourceMapPanelRect(ebId, mapPanelRect);
    await saveSourceFullSheetPath(ebId, fullSheetPath);
    final metadata = isPdf ? HloPdfMetadataParser.parseBytes(source.bytes) : null;
    final seed = await MissionSeedLocationResolver().resolve(
      metadata: metadata,
      userLat: userLat,
      userLng: userLng,
    );
    return ManualUploadDraft(
      mapBytes: rendered,
      layoutPath: layoutPath,
      mapFilePath: source.name,
      seed: seed,
      metadata: metadata,
      pageSize: pageSize,
    );
  }

  Future<void> saveSourceLayoutInsets(String ebId, HloLayoutSheetInsets insets) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'sourceLayoutInsets': insets.toJson(),
      },
    ));
  }

  Future<void> saveSourceMapPanelRect(String ebId, HloMapPanelRect rect) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'sourceMapPanelRect': rect.toJson(),
      },
    ));
  }

  Future<void> saveSourceFullSheetPath(String ebId, String path) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'sourceFullSheetPath': path,
      },
    ));
  }

  Future<void> saveSourcePageSize(String ebId, HloPdfPageSize pageSize) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'sourcePageSizePt': pageSize.toJson(),
      },
    ));
  }

  /// Trace the thick white HLB border on demand.
  Future<List<({double x, double y})>> trackBoundary(
    Uint8List bytes, {
    HloPdfMetadata? metadata,
  }) async {
    double? blockCenterX;
    double? blockCenterY;
    if (!kIsWeb && metadata?.ebNo != null) {
      final ocr = MapPanelOcrService();
      try {
        final center = await ocr.findEbBlockCenter(bytes, metadata!.ebNo!);
        if (center != null) {
          blockCenterX = center.x;
          blockCenterY = center.y;
        }
      } finally {
        await ocr.dispose();
      }
    }

    final job = TrackBoundaryJob(
      bytes: bytes,
      blockCenterX: blockCenterX,
      blockCenterY: blockCenterY,
    );
    final ring = kIsWeb ? runTrackBoundaryJob(job) : await compute(runTrackBoundaryJob, job);

    if (ring.length < 3) {
      throw Exception('Could not trace white boundary — zoom in and try again');
    }
    return ring;
  }

  Future<MissionIntelligencePackage> buildIntelligenceFromManual({
    required ManualUploadDraft draft,
    required List<({double x, double y})> uvRing,
    required List<GeorefControlPoint> controlPoints,
  }) async {
    if (uvRing.length < 3) {
      throw Exception('Trace the white HLB boundary first');
    }
    if (controlPoints.length < kMinGeorefMatchedPins) {
      throw Exception('Match at least $kMinGeorefMatchedPins pins to Google Maps locations');
    }
    _validateControlPoints(controlPoints);

    final boundaryUv = uvRing.map((p) => UvPoint(p.x, p.y)).toList();
    final aligned = SatelliteAlignMath.alignFromControlPoints(controlPoints, uvRing);
    final imageBounds = aligned.imageBounds;
    final gpsBoundary = aligned.gpsBoundary;
    final affineMatrix = aligned.affineMatrix;

    final boundaryConfidence = 0.92;
    const structuresConfidence = 0.0;
    final overall = (boundaryConfidence * 0.35 + 0.25).clamp(0.0, 1.0);

    const observationTargets = <Map<String, dynamic>>[];

    final alignmentBlock = {
      'autoAligned': true,
      'method': 'manual_pins',
      'qualityPercent': LandmarkAnchorService.qualityPercentFromRms(aligned.rmsErrorMeters),
      'score': aligned.alignmentLabel.toLowerCase().replaceAll(' ', '_'),
      'imageBounds': imageBounds.toJson(),
      'affineMatrix': affineMatrix,
      'rmsErrorMeters': aligned.rmsErrorMeters.round(),
      'alignmentLabel': aligned.alignmentLabel,
      'controlPoints': controlPoints.map((p) => p.toJson()).toList(),
    };

    final intelligenceJson = {
      'generatedAt': DateTime.now().toIso8601String(),
      'engine': 'spatial_cv',
      'engineVersion': spatialCvVersion,
      'alignment': alignmentBlock,
      'confidence': {
        'boundary': boundaryConfidence,
        'structures': structuresConfidence,
        'roads': 0.25,
        'landmarks': 0.05,
        'alignment': aligned.rmsErrorMeters < 80 ? 0.9 : 0.6,
        'overall': overall,
      },
      'boundary': {
        'source': 'manual_tracked',
        'confidence': boundaryConfidence,
        'gpsRing': gpsBoundary.map((p) => p.toJson()).toList(),
        'uvRing': uvRing.map((p) => {'x': p.x, 'y': p.y}).toList(),
      },
      'hypotheses': {
        'observationTargets': observationTargets,
        'roads': const [],
        'landmarks': const [],
        'waterBodies': const [],
        'canalCrossings': const [],
        'vegetationPatches': const [],
      },
      'summary': {
        'observationTargets': observationTargets.length,
        'roadSegments': 0,
        'possibleLandmarks': controlPoints.length,
        'canalCrossings': 0,
        'vegetationPatches': 0,
      },
      'layoutImagePath': draft.layoutPath,
    };

    return MissionIntelligencePackage.fromJson(intelligenceJson);
  }

  void _validateControlPoints(List<GeorefControlPoint> points) {
    if (points.length < 2) return;
    var maxUvDist = 0.0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final du = points[j].sketchX - points[i].sketchX;
        final dv = points[j].sketchY - points[i].sketchY;
        maxUvDist = math.max(maxUvDist, math.sqrt(du * du + dv * dv));
      }
    }
    if (maxUvDist < 0.06) {
      throw Exception(
        'Landmarks too close on the PDF map — confirm two that are far apart (e.g. church and school).',
      );
    }
  }

  Future<MissionIntelligencePackage> generateIntelligence({
    required String ebId,
    required File mapFile,
    required double seedLat,
    required double seedLng,
    MissionSeedLocation? seedLocation,
    List<GeorefControlPoint>? controlPoints,
  }) async {
    final draft = await prepareImport(
      ebId: ebId,
      mapFile: mapFile,
      userLat: seedLat,
      userLng: seedLng,
    );
    return buildIntelligence(
      draft: draft,
      seedLocation: seedLocation ?? draft.anchorPrep.seed,
      controlPoints: controlPoints,
    );
  }

  Future<Uint8List> _loadMapBytes(File file) async {
    return _renderMapBytes(await file.readAsBytes(), file.path);
  }

  Future<({Uint8List bytes, String name})> _readMapSource({
    File? mapFile,
    Uint8List? mapBytes,
    String? mapFileName,
  }) async {
    if (mapBytes != null) {
      return (bytes: mapBytes, name: mapFileName ?? 'upload.pdf');
    }
    if (mapFile != null) {
      return (bytes: await mapFile.readAsBytes(), name: mapFile.path);
    }
    throw Exception('No map file provided');
  }

  /// Map panel only (no legend sidebar or page margins) for satellite ground overlay.
  Future<Uint8List> _renderMapBytes(Uint8List data, String name) async {
    final lower = name.toLowerCase();
    final sourceBytes = lower.endsWith('.pdf') ? await renderHloPdfPagePng(data) : data;
    return prepareLayoutMapImageBytes(sourceBytes);
  }

  Future<void> saveImageBounds(String ebId, ImageBounds bounds) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'imageBounds': bounds.toJson(),
      },
    ));
  }

  Future<void> saveGpsBoundary(String ebId, List<GpsPoint> boundary) async {
    final state = await _cache.get(ebId);
    if (state == null) return;
    final closed = [...boundary.map((p) => [p.lng, p.lat])];
    if (closed.isNotEmpty) closed.add(closed.first);
    await _cache.put(state.copyWith(
      layoutGeoref: {
        ...?state.layoutGeoref,
        'gpsBoundary': boundary.map((p) => p.toJson()).toList(),
        'boundaryPolygon': {
          'type': 'Polygon',
          'coordinates': [closed],
        },
        'polygonAreaSqMeters': SatelliteAlignMath.polygonAreaSqMeters(boundary),
      },
    ));
  }

  /// Load saved layout + intelligence for post-confirm boundary reorientation.
  Future<ReorientSession?> loadReorientSession(String ebId) async {
    final state = await _cache.get(ebId);
    if (state == null || !state.hasOfficialBoundary) return null;

    final intelRaw = state.missionIntelligence ??
        state.layoutGeoref?['missionIntelligence'];
    if (intelRaw is! Map) return null;

    final intelMap = deepJsonMap(intelRaw);
    var layoutPath = intelMap['layoutImagePath'] as String?;
    if (layoutPath == null || !await missionLayoutExists(layoutPath)) {
      layoutPath = await defaultMissionLayoutRef(ebId);
    }
    if (layoutPath == null || !await missionLayoutExists(layoutPath)) return null;

    final intel = MissionIntelligencePackage.fromJson(intelMap);
    if (intel.gpsBoundary.length < 3) return null;

    return ReorientSession(layoutImagePath: layoutPath, intelligence: intel);
  }

  /// Persist a rigid boundary nudge after the mission was already confirmed.
  Future<void> applyReorientedBoundary({
    required String ebId,
    required Map<String, dynamic> intelligence,
    required List<GpsPoint> gpsBoundary,
    ImageBounds? imageBounds,
  }) async {
    final state = await _cache.get(ebId);
    if (state == null) throw Exception('HLB not found');

    final uvRing = resolveMissionUvRing(
      intelligenceMap: intelligence,
      layoutGeoref: state.layoutGeoref,
    );
    final boundary = resolveMissionGpsBoundary(
      storedRing: gpsBoundary,
      uvRing: uvRing,
      imageBounds: imageBounds,
    );
    if (boundary.length < 3) throw Exception('Boundary not ready');

    final closed = [...boundary.map((p) => [p.lng, p.lat]), [boundary.first.lng, boundary.first.lat]];
    final start = SatelliteAlignMath.northWestStartPoint(boundary);
    final area = SatelliteAlignMath.polygonAreaSqMeters(boundary);
    final existing = state.officialBoundary;

    if (uvRing.length >= 3) {
      final boundaryMeta = Map<String, dynamic>.from(intelligence['boundary'] as Map? ?? {});
      boundaryMeta['gpsRing'] = boundary.map((p) => p.toJson()).toList();
      boundaryMeta['uvRing'] = uvRing.map((p) => {'x': p.x, 'y': p.y}).toList();
      intelligence['boundary'] = boundaryMeta;
    }

    if (imageBounds != null) {
      final alignment = Map<String, dynamic>.from(intelligence['alignment'] as Map? ?? {});
      alignment['imageBounds'] = imageBounds.toJson();
      alignment.remove('affineMatrix');
      alignment['method'] = 'pdf_overlay_fine_tune';
      intelligence['alignment'] = alignment;
    }

    final official = existing != null
        ? LocalOfficialBoundary(
            id: existing.id,
            hlbCode: existing.hlbCode,
            name: existing.name,
            boundaryPolygon: {'type': 'Polygon', 'coordinates': [closed]},
            areaSqMeters: area,
            startLat: start.lat,
            startLng: start.lng,
            northDescription: existing.northDescription,
            southDescription: existing.southDescription,
            eastDescription: existing.eastDescription,
            westDescription: existing.westDescription,
            source: existing.source,
            importedAt: existing.importedAt,
          )
        : null;

    await _cache.put(state.copyWith(
      missionIntelligence: intelligence,
      officialBoundary: official ?? state.officialBoundary,
      layoutGeoref: {
        ...?state.layoutGeoref,
        'missionIntelligence': intelligence,
        'gpsBoundary': boundary.map((p) => p.toJson()).toList(),
        if (imageBounds != null) 'imageBounds': imageBounds.toJson(),
        if (uvRing.length >= 3) 'uvRing': uvRing.map((p) => {'x': p.x, 'y': p.y}).toList(),
        'boundaryPolygon': {'type': 'Polygon', 'coordinates': [closed]},
        'polygonAreaSqMeters': area,
      },
    ));
  }

  Future<void> finalizeMission({
    required String ebId,
    required String ebCode,
    required Map<String, dynamic> intelligence,
    required List<GpsPoint> gpsBoundary,
  }) async {
    if (gpsBoundary.length < 3) throw Exception('Boundary not ready');

    final state = await _cache.get(ebId);
    if (state == null) throw Exception('HLB not initialized');

    final closed = [...gpsBoundary.map((p) => [p.lng, p.lat]), [gpsBoundary.first.lng, gpsBoundary.first.lat]];
    final start = SatelliteAlignMath.northWestStartPoint(gpsBoundary);
    final area = SatelliteAlignMath.polygonAreaSqMeters(gpsBoundary);

    final official = LocalOfficialBoundary(
      id: ebId,
      hlbCode: ebCode,
      name: state.ebCode,
      boundaryPolygon: {'type': 'Polygon', 'coordinates': [closed]},
      areaSqMeters: area,
      startLat: start.lat,
      startLng: start.lng,
      source: 'layout_map',
      importedAt: DateTime.now(),
    );

    final intel = MissionIntelligencePackage.fromJson(intelligence);
    final boundaryMeta = intelligence['boundary'] as Map<String, dynamic>? ?? {};
    final closedRing = [...gpsBoundary.map((p) => [p.lng, p.lat]), [gpsBoundary.first.lng, gpsBoundary.first.lat]];

    await _cache.put(state.copyWith(
      phase: 'mapping',
      blockStatus: 'published',
      missionIntelligence: intelligence,
      officialBoundary: official,
      layoutGeoref: {
        ...?state.layoutGeoref,
        'missionIntelligence': intelligence,
        'gpsBoundary': gpsBoundary.map((p) => p.toJson()).toList(),
        'boundaryPolygon': {'type': 'Polygon', 'coordinates': [closedRing]},
        'polygonAreaSqMeters': area,
        'imageBounds': intel.imageBounds.toJson(),
        if (boundaryMeta['uvRing'] != null) 'uvRing': boundaryMeta['uvRing'],
        if (intelligence['layoutImagePath'] != null)
          'layoutImagePath': intelligence['layoutImagePath'],
        'status': 'finalized',
        'finalizedAt': DateTime.now().toIso8601String(),
      },
    ));
  }
}

class ReorientSession {
  const ReorientSession({
    required this.layoutImagePath,
    required this.intelligence,
  });

  final String layoutImagePath;
  final MissionIntelligencePackage intelligence;
}

class AlignmentRestartSession {
  const AlignmentRestartSession({
    required this.layoutImagePath,
    required this.mapBytes,
    required this.uvRing,
    required this.pins,
    required this.seed,
  });

  final String layoutImagePath;
  final Uint8List mapBytes;
  final List<({double x, double y})> uvRing;
  final List<PdfGeorefPin> pins;
  final MissionSeedLocation seed;
}
