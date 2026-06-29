import 'dart:math' as math;

import '../models/mission_models.dart' as models;
import '../models/mission_models.dart';
import 'hlb_geo_engine.dart';
import 'hlb_local_state.dart';
import 'hlb_official_catalog.dart';

/// Derives discovery, gaps, and draft map entirely from local HLB state.
class HlbStateComputer {
  static List<({double lat, double lng})> _officialRing(HlbLocalState s) => s.officialBoundaryRing;

  static List<GpsCoord> _vertices(HlbLocalState s) {
    final ring = _officialRing(s);
    if (ring.isNotEmpty) return ring.map((p) => GpsCoord(p.lat, p.lng)).toList();
    return s.boundaryVertices.map((v) => GpsCoord(v.latitude, v.longitude)).toList();
  }

  static List<GpsCoord> _breadcrumbs(HlbLocalState s) {
    final bc = s.breadcrumbs.map((b) => GpsCoord(b.latitude, b.longitude)).toList();
    final ring = _officialRing(s);
    if (ring.isEmpty) return bc;
    return HlbGeoEngine.filterInsidePolygon(bc, ring);
  }

  static List<GpsBuilding> _buildings(HlbLocalState s) => s.buildings
      .map((b) => GpsBuilding(b.localId, b.latitude, b.longitude, b.buildingNumber))
      .toList();

  static MapBounds _bounds(HlbLocalState s) {
    final ring = _officialRing(s);
    final all = <GpsCoord>[
      ...ring.map((p) => GpsCoord(p.lat, p.lng)),
      ..._buildings(s).map((b) => GpsCoord(b.latitude, b.longitude)),
      ..._breadcrumbs(s),
    ];
    if (all.isEmpty) return const MapBounds(10, 10.001, 76, 76.001);
    return HlbGeoEngine.computeBounds(all);
  }

  static bool _hasOfficial(HlbLocalState s) => s.hasOfficialBoundary;

  static bool _gapInsideBoundary(HlbLocalState s, double? lat, double? lng) {
    if (lat == null || lng == null) return true;
    final ring = _officialRing(s);
    if (ring.isEmpty) return true;
    return HlbGeoEngine.pointInPolygon(lat, lng, ring);
  }

  static List<CoverageGap> detectGaps(HlbLocalState state, {double? enumLat, double? enumLng}) {
    final bounds = _bounds(state);
    final bc = _breadcrumbs(state);
    final buildings = _buildings(state);
    final vertices = _vertices(state);
    final pathMeters = HlbGeoEngine.pathWalkedMeters(bc);
    final closed = _hasOfficial(state) || HlbGeoEngine.boundaryClosed(vertices);
    final resolutionMap = {for (final r in state.gapResolutions) r.gapFingerprint: r};

    final raw = <_RawGap>[];

    if (bc.length >= 8 && buildings.isNotEmpty) {
      for (var i = 0; i < bc.length; i += 6) {
        final slice = bc.skip(i).take(6).toList();
        if (slice.isEmpty) continue;
        final lat = slice.map((p) => p.latitude).reduce((a, b) => a + b) / slice.length;
        final lng = slice.map((p) => p.longitude).reduce((a, b) => a + b) / slice.length;
        if (!_gapInsideBoundary(state, lat, lng)) continue;
        final nearby = HlbGeoEngine.nearbyBuildings(lat, lng, buildings, 100);
        final atPoint = HlbGeoEngine.nearbyBuildings(lat, lng, buildings, 45);
        if (nearby >= 3 && atPoint == 0) {
          raw.add(_RawGap(
            id: HlbGeoEngine.gapFingerprint('road_without_building', 'dense_corridor', lat, lng),
            type: 'road_without_building',
            reason: 'dense_corridor',
            severity: 'high',
            title: 'Road segment without building',
            description: 'Walked road with nearby buildings on both sides — no structure recorded here',
            lat: lat,
            lng: lng,
          ));
        }
      }
    }

    for (final c in HlbGeoEngine.findUnrecordedClusters(bc, buildings)) {
      if (!_gapInsideBoundary(state, c.lat, c.lng)) continue;
      final nearby = HlbGeoEngine.nearbyBuildings(c.lat, c.lng, buildings, 120);
      raw.add(_RawGap(
        id: HlbGeoEngine.gapFingerprint('empty_cluster', 'walk_no_building', c.lat, c.lng),
        type: 'empty_cluster',
        reason: 'walk_no_building',
        severity: nearby >= 2 ? 'high' : 'medium',
        title: nearby >= 2 ? 'Dense area — no building recorded' : 'Walked area — no building recorded',
        description: nearby >= 2
            ? 'Path passed through area surrounded by buildings — confirm no structure was missed'
            : 'Walk path with no building confirmed nearby',
        lat: c.lat,
        lng: c.lng,
      ));
    }

    for (final cell in HlbGeoEngine.findUnvisitedGridCells(bc, bounds)) {
      if (!_gapInsideBoundary(state, cell.lat, cell.lng)) continue;
      final nearby = HlbGeoEngine.nearbyBuildings(cell.lat, cell.lng, buildings, 80);
      raw.add(_RawGap(
        id: HlbGeoEngine.gapFingerprint('unwalked_road', 'grid_${cell.cx}_${cell.cy}', cell.lat, cell.lng),
        type: 'unwalked_road',
        reason: 'grid_${cell.cx}_${cell.cy}',
        severity: nearby >= 2 ? 'high' : nearby == 0 ? 'low' : 'medium',
        title: nearby >= 2 ? 'Unwalked road near buildings' : 'Area not yet walked',
        description: nearby >= 2
            ? 'Road segment near recorded buildings has not been traversed'
            : 'Block area with no walk coverage — may be open land or canal bank',
        lat: cell.lat,
        lng: cell.lng,
      ));
    }

    if (!_hasOfficial(state)) {
      if (vertices.isNotEmpty && !closed && vertices.length >= 2) {
        final lat = (vertices.first.latitude + vertices.last.latitude) / 2;
        final lng = (vertices.first.longitude + vertices.last.longitude) / 2;
        raw.add(_RawGap(
          id: HlbGeoEngine.gapFingerprint('boundary_gap', 'loop_not_closed', null, null),
          type: 'boundary_gap',
          reason: 'loop_not_closed',
          severity: 'high',
          title: 'Boundary loop not closed',
          description: 'HLB perimeter walk is open — return to start corner to close the boundary',
          lat: lat,
          lng: lng,
        ));
      } else if (vertices.isEmpty) {
        final last = bc.isNotEmpty ? bc.last : null;
        raw.add(_RawGap(
          id: HlbGeoEngine.gapFingerprint('boundary_gap', 'no_boundary', null, null),
          type: 'boundary_gap',
          reason: 'no_boundary',
          severity: 'high',
          title: 'No HLB boundary recorded',
          description: 'Walk the block perimeter and mark boundary corners',
          lat: last?.latitude,
          lng: last?.longitude,
        ));
      }
    }

    if (pathMeters > 400 && state.buildings.isEmpty && bc.isNotEmpty) {
      final last = bc.last;
      raw.add(_RawGap(
        id: HlbGeoEngine.gapFingerprint('unrecorded_walk', 'walk_without_buildings', null, null),
        type: 'unrecorded_walk',
        reason: 'walk_without_buildings',
        severity: 'high',
        title: 'Area walked — zero buildings',
        description: 'Significant walk distance with no buildings confirmed — verify each structure',
        lat: last.latitude,
        lng: last.longitude,
      ));
    }

    final seen = <String>{};
    final gaps = <CoverageGap>[];
    for (final g in raw) {
      if (seen.contains(g.id)) continue;
      seen.add(g.id);
      final res = resolutionMap[g.id];
      double? dist;
      double? bearing;
      String? distLabel;
      double? mapX;
      double? mapY;
      if (g.lat != null && g.lng != null) {
        final coords = HlbGeoEngine.projectToMap(g.lat!, g.lng!, bounds);
        mapX = coords.x;
        mapY = coords.y;
        if (enumLat != null && enumLng != null) {
          dist = HlbGeoEngine.haversineMeters(enumLat, enumLng, g.lat!, g.lng!);
          bearing = HlbGeoEngine.bearingDegrees(enumLat, enumLng, g.lat!, g.lng!);
          distLabel = HlbGeoEngine.formatDistance(dist);
        }
      }
      gaps.add(CoverageGap(
        id: g.id,
        type: g.type,
        reason: g.reason,
        severity: g.severity,
        title: g.title,
        description: g.description,
        latitude: g.lat,
        longitude: g.lng,
        mapX: mapX,
        mapY: mapY,
        distanceMeters: dist,
        bearingDegrees: bearing,
        distanceLabel: distLabel,
        resolution: res != null
            ? GapResolution(status: res.resolution, resolvedAt: res.resolvedAt.toIso8601String(), notes: res.notes)
            : null,
      ));
    }

    int severityRank(String s) => s == 'high' ? 0 : s == 'medium' ? 1 : 2;
    gaps.sort((a, b) {
      if (a.isResolved != b.isResolved) return a.isResolved ? 1 : -1;
      final sd = severityRank(a.severity).compareTo(severityRank(b.severity));
      if (sd != 0) return sd;
      return (a.distanceMeters ?? 99999).compareTo(b.distanceMeters ?? 99999);
    });
    return gaps;
  }

  static GapSummary summarizeGaps(List<CoverageGap> gaps) {
    final open = gaps.where((g) => !g.isResolved).toList();
    return GapSummary(
      total: gaps.length,
      open: open.length,
      resolved: gaps.length - open.length,
      highPriority: open.where((g) => g.severity == 'high').length,
      mediumPriority: open.where((g) => g.severity == 'medium').length,
      lowPriority: open.where((g) => g.severity == 'low').length,
    );
  }

  static DiscoveryStatus discovery(HlbLocalState state, {double? enumLat, double? enumLng}) {
    final bounds = _bounds(state);
    final bc = _breadcrumbs(state);
    final vertices = _vertices(state);
    final buildings = _buildings(state);
    final pathMeters = HlbGeoEngine.pathWalkedMeters(bc);
    final ring = _officialRing(state);
    final roadCoverage = ring.isNotEmpty
        ? HlbGeoEngine.estimateCoverageInsidePolygon(
            state.breadcrumbs.map((b) => GpsCoord(b.latitude, b.longitude)).toList(),
            ring,
          )
        : HlbGeoEngine.estimatePathCoveragePercent(bc, bounds);
    final closed = _hasOfficial(state) || HlbGeoEngine.boundaryClosed(vertices);
    final gaps = detectGaps(state, enumLat: enumLat, enumLng: enumLng);
    final summary = summarizeGaps(gaps);
    final openGaps = gaps.where((g) => !g.isResolved).toList();

    var boundaryPct = 0;
    if (_hasOfficial(state)) {
      boundaryPct = roadCoverage;
    } else if (closed) {
      boundaryPct = 100;
    } else if (vertices.length >= 3) {
      boundaryPct = (vertices.length / 12 * 100).round().clamp(0, 90);
    }

    var walkingMinutes = 0;
    if (state.breadcrumbs.length >= 2) {
      walkingMinutes = state.breadcrumbs.last.recordedAt
          .difference(state.breadcrumbs.first.recordedAt)
          .inMinutes
          .clamp(0, 9999);
    }

    final nextNum = state.buildings.isEmpty
        ? 1
        : state.buildings.map((b) => b.buildingNumber).reduce((a, b) => a > b ? a : b) + 1;

    final warnings = openGaps
        .where((g) => g.severity == 'high')
        .take(3)
        .map((g) => ZeroExclusionWarning(reason: g.type, description: g.description, severity: g.severity))
        .toList();

    final ordered = HlbGeoEngine.serpentineOrder(buildings);
    final numberingIssues = <NumberingIssue>[];
    for (var i = 0; i < ordered.length; i++) {
      final expected = i + 1;
      final bn = ordered[i].buildingNumber;
      if (bn != null && bn != expected) {
        numberingIssues.add(NumberingIssue(
          buildingId: ordered[i].id,
          buildingNumber: bn,
          expectedNumber: expected,
          expectedLabel: HlbGeoEngine.formatCn(expected),
        ));
      }
    }
    if (numberingIssues.isNotEmpty) {
      warnings.add(ZeroExclusionWarning(
        reason: 'numbering_mismatch',
        description: '${numberingIssues.length} building(s) out of NW→SE serpentine order',
        severity: 'medium',
      ));
    }

    final official = state.officialBoundary;
    double? startDist;
    double? startBearing;
    String? startDistLabel;
    if (official != null && enumLat != null && enumLng != null) {
      startDist = HlbGeoEngine.haversineMeters(enumLat, enumLng, official.startLat, official.startLng);
      startBearing = HlbGeoEngine.bearingDegrees(enumLat, enumLng, official.startLat, official.startLng);
      startDistLabel = HlbGeoEngine.formatDistance(startDist);
    }

    return DiscoveryStatus(
      ebId: state.ebId,
      ebCode: state.ebCode,
      phase: state.phase,
      boundaryCoveragePercent: boundaryPct,
      roadCoveragePercent: roadCoverage,
      pathWalkedMeters: pathMeters.round(),
      pathWalkedLabel: pathMeters >= 1000 ? '${(pathMeters / 1000).toStringAsFixed(1)} km walked' : '${pathMeters.round()} m walked',
      walkingTimeMinutes: walkingMinutes,
      walkingTimeLabel: walkingMinutes >= 60
          ? '${walkingMinutes ~/ 60}h ${walkingMinutes % 60}m'
          : walkingMinutes > 0
              ? '${walkingMinutes}m'
              : '—',
      buildingsDiscovered: state.buildings.length,
      landmarksDiscovered: state.landmarks.length,
      boundaryVertices: vertices.length,
      boundaryClosed: closed,
      suggestedNextBuildingNumber: nextNum,
      suggestedNextLabel: HlbGeoEngine.formatCn(nextNum),
      numberingIssues: numberingIssues,
      gapSummary: summary,
      zeroExclusionWarnings: warnings,
      coverageGaps: openGaps.take(8).toList(),
      hasOfficialBoundary: _hasOfficial(state),
      officialBoundaryAreaLabel: official?.areaLabel,
      startPointDistanceLabel: startDistLabel,
      startPointBearing: startBearing,
      startPointReached: state.boundaryAudit?.startPointReachedAt != null,
      boundarySource: official?.source,
    );
  }

  static CoverageGapsResponse coverageGaps(HlbLocalState state, {double? enumLat, double? enumLng}) {
    final gaps = detectGaps(state, enumLat: enumLat, enumLng: enumLng);
    return CoverageGapsResponse(
      ebId: state.ebId,
      ebCode: state.ebCode,
      summary: summarizeGaps(gaps),
      gaps: gaps,
    );
  }

  static DraftHlbMap draftMap(HlbLocalState state) {
    final bounds = _bounds(state);
    final vertices = _vertices(state);
    final closed = _hasOfficial(state) || HlbGeoEngine.boundaryClosed(vertices);

    final boundary = vertices.length >= 2
        ? vertices.map((v) {
            final p = HlbGeoEngine.projectToMap(v.latitude, v.longitude, bounds);
            return models.MapPoint(p.x, p.y);
          }).toList()
        : <models.MapPoint>[];

    final allBc = state.breadcrumbs.map((b) => GpsCoord(b.latitude, b.longitude)).toList();
    final ring = _officialRing(state);
    final bc = ring.isNotEmpty ? HlbGeoEngine.filterInsidePolygon(allBc, ring) : allBc;
    final step = bc.isEmpty ? 1 : (bc.length / 200).ceil().clamp(1, bc.length);
    final walkPath = <models.MapPoint>[];
    for (var i = 0; i < bc.length; i += step) {
      final p = HlbGeoEngine.projectToMap(bc[i].latitude, bc[i].longitude, bounds);
      walkPath.add(models.MapPoint(p.x, p.y));
    }

    final buildings = state.buildings.map((b) {
      final p = HlbGeoEngine.projectToMap(b.latitude, b.longitude, bounds);
      return DraftMapBuilding(
        id: b.localId,
        buildingNumber: b.buildingNumber,
        censusHouseCount: b.censusHouseCount,
        buildingType: b.buildingType,
        mapX: p.x,
        mapY: p.y,
        label: '${b.buildingNumber} (${b.censusHouseCount})',
      );
    }).toList();

    final landmarks = state.landmarks.map((l) {
      final p = HlbGeoEngine.projectToMap(l.latitude, l.longitude, bounds);
      return DraftMapLandmark(
        name: l.name,
        type: HlbOfficialCatalog.normalizeLandmarkType(l.landmarkType),
        mapX: p.x,
        mapY: p.y,
      );
    }).toList();

    final ordered = HlbGeoEngine.serpentineOrder(_buildings(state));
    final serpentine = ordered.asMap().entries.map((e) {
      return SerpentineEntry(
        buildingId: e.value.id,
        sequence: e.key + 1,
        label: HlbGeoEngine.formatCn(e.key + 1),
      );
    }).toList();

    final buildingCoords = {
      for (final b in state.buildings)
        b.localId: HlbGeoEngine.projectToMap(b.latitude, b.longitude, bounds),
    };
    final serpentineArrows = <SerpentineArrow>[];
    for (var i = 0; i < ordered.length - 1; i++) {
      final from = buildingCoords[ordered[i].id];
      final to = buildingCoords[ordered[i + 1].id];
      if (from == null || to == null) continue;
      serpentineArrows.add(SerpentineArrow(
        fromX: from.x,
        fromY: from.y,
        toX: to.x,
        toY: to.y,
        sequence: i + 1,
      ));
    }

    final lineFeatures = state.roadSegments.map((seg) {
      final pts = seg.points
          .map((p) {
            final proj = HlbGeoEngine.projectToMap(p.lat, p.lng, bounds);
            return models.MapPoint(proj.x, proj.y);
          })
          .toList();
      return DraftMapLineFeature(
        id: seg.localId,
        segmentType: HlbOfficialCatalog.normalizeLineType(seg.segmentType),
        name: seg.name,
        points: pts,
        labelRotation: _segmentLabelRotationDegrees(pts),
      );
    }).toList();

    final annotations = state.mapAnnotations
        .map(
          (a) => DraftMapAnnotation(
            text: a.text,
            annotationType: a.annotationType,
            mapX: a.mapX,
            mapY: a.mapY,
            rotationDegrees: a.rotationDegrees,
          ),
        )
        .toList();

    DraftMapEndpoint? startPoint;
    DraftMapEndpoint? endPoint;
    if (ordered.isNotEmpty) {
      final firstId = ordered.first.id;
      final lastId = ordered.last.id;
      final firstB = _buildingById(state.buildings, firstId);
      final lastB = _buildingById(state.buildings, lastId);
      if (firstB != null) {
        final p = HlbGeoEngine.projectToMap(firstB.latitude, firstB.longitude, bounds);
        startPoint = DraftMapEndpoint(
          label: 'Starting Point',
          mapX: p.x,
          mapY: p.y,
          buildingNumber: firstB.buildingNumber,
        );
      }
      if (lastB != null && lastB.localId != firstId) {
        final p = HlbGeoEngine.projectToMap(lastB.latitude, lastB.longitude, bounds);
        endPoint = DraftMapEndpoint(
          label: 'Ending Point',
          mapX: p.x,
          mapY: p.y,
          buildingNumber: lastB.buildingNumber,
        );
      }
    }

    final pdfMeta = state.layoutGeoref?['pdfMetadata'];
    DraftHlbTitleBlock titleBlock;
    if (pdfMeta is Map) {
      final meta = Map<String, dynamic>.from(pdfMeta);
      titleBlock = DraftHlbTitleBlock(
        ebCode: state.ebCode,
        stateName: meta['stateName'] as String?,
        stateCode: meta['stateCode'] as String?,
        district: meta['district'] as String?,
        districtCode: meta['districtCode'] as String?,
        subDistrict: meta['subDistrict'] as String?,
        subDistrictCode: meta['subDistrictCode'] as String?,
        townVillage: meta['townVillage'] as String?,
        townCode: meta['townCode'] as String?,
        wardNo: meta['wardNo'] as String?,
        subBlockNo: meta['subBlockNo'] as String?,
      );
    } else {
      titleBlock = DraftHlbTitleBlock(ebCode: state.ebCode);
    }

    DraftHlbFooterBlock footerBlock;
    final footerRaw = state.layoutGeoref?['layoutMapFooter'];
    if (footerRaw is Map) {
      footerBlock = DraftHlbFooterBlock.fromJson(Map<String, dynamic>.from(footerRaw));
    } else {
      footerBlock = const DraftHlbFooterBlock();
    }

    return DraftHlbMap(
      ebId: state.ebId,
      ebCode: state.ebCode,
      boundary: boundary,
      boundaryClosed: closed,
      buildings: buildings,
      landmarks: landmarks,
      walkPath: walkPath,
      serpentineOrder: serpentine,
      lineFeatures: lineFeatures,
      serpentineArrows: serpentineArrows,
      titleBlock: titleBlock,
      footerBlock: footerBlock,
      annotations: annotations,
      startPoint: startPoint,
      endPoint: endPoint,
      isOfficialBoundary: _hasOfficial(state),
    );
  }

  static LocalBuilding? _buildingById(List<LocalBuilding> buildings, String id) {
    for (final b in buildings) {
      if (b.localId == id) return b;
    }
    return null;
  }

  static double _segmentLabelRotationDegrees(List<models.MapPoint> pts) {
    if (pts.length < 2) return 0;
    final mid = pts.length ~/ 2;
    final a = pts[mid - 1];
    final b = pts[mid];
    final radians = math.atan2(b.y - a.y, b.x - a.x);
    return radians * 180 / math.pi;
  }

  static ZeroExclusionValidation validate(HlbLocalState state) {
    final d = discovery(state);
    final warnings = List<ZeroExclusionWarning>.from(d.zeroExclusionWarnings);
    if (state.ignoredSuggestions.isNotEmpty) {
      warnings.add(ZeroExclusionWarning(
        reason: 'ignored_suggestions',
        description:
            '${state.ignoredSuggestions.length} observation target(s) ignored — review before finalizing',
        severity: 'medium',
      ));
    }
    final boundaryOk = d.hasOfficialBoundary || d.boundaryClosed;
    return ZeroExclusionValidation(
      canFinalize: boundaryOk && d.buildingsDiscovered > 0 && d.gapSummary.highPriority == 0,
      warnings: warnings,
      coverageGaps: d.coverageGaps,
      numberingIssues: d.numberingIssues,
      gapSummary: d.gapSummary,
      ignoredSuggestionsCount: state.ignoredSuggestions.length,
    );
  }

  static int suggestNumber(HlbLocalState state, double lat, double lng) {
    return HlbGeoEngine.suggestSerpentineNumber(lat, lng, _buildings(state));
  }

  static bool isInsideOfficialBoundary(HlbLocalState state, double lat, double lng) {
    final ring = _officialRing(state);
    if (ring.isEmpty) return true;
    return HlbGeoEngine.pointInPolygon(lat, lng, ring);
  }
}

class _RawGap {
  _RawGap({
    required this.id,
    required this.type,
    required this.reason,
    required this.severity,
    required this.title,
    required this.description,
    this.lat,
    this.lng,
  });
  final String id;
  final String type;
  final String reason;
  final String severity;
  final String title;
  final String description;
  final double? lat;
  final double? lng;
}
