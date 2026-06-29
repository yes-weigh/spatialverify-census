import 'package:flutter/material.dart';

enum MissionBuildingStatus { notVisited, visited, completed, revisitRequired }

enum EditorMode { boundary, building, landmark, route }

class MapPoint {
  const MapPoint(this.x, this.y);
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory MapPoint.fromJson(Map<String, dynamic> json) =>
      MapPoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

class EnumerationBlock {
  const EnumerationBlock({
    required this.id,
    required this.projectId,
    required this.ebCode,
    this.name,
    required this.status,
    this.progressPercent = 0,
    this.totalBuildings = 0,
  });

  final String id;
  final String projectId;
  final String ebCode;
  final String? name;
  final String status;
  final double progressPercent;
  final int totalBuildings;

  bool get isComplete => status == 'published' && progressPercent >= 100;
  bool get isMappingPhase => status == 'draft' || (status == 'published' && totalBuildings == 0);

  factory EnumerationBlock.fromJson(Map<String, dynamic> json) {
    final total = json['total_buildings'] as int? ?? 0;
    final completed = json['completed_buildings'] as int? ?? 0;
    final progress = total > 0 ? (completed / total) * 100 : 0.0;
    return EnumerationBlock(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      ebCode: json['eb_code'] as String,
      name: json['name'] as String?,
      status: json['status'] as String,
      progressPercent: progress,
      totalBuildings: total,
    );
  }
}

class MissionBuilding {
  MissionBuilding({
    required this.id,
    required this.ebId,
    required this.buildingNumber,
    required this.censusHouseCount,
    required this.buildingType,
    required this.mapX,
    required this.mapY,
    required this.status,
    this.notes,
    this.routeSequence,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String ebId;
  final int buildingNumber;
  final int censusHouseCount;
  final String buildingType;
  final double mapX;
  final double mapY;
  final String status;
  final String? notes;
  final int? routeSequence;
  final double? latitude;
  final double? longitude;

  String get label => '$buildingNumber ($censusHouseCount)';

  factory MissionBuilding.fromJson(Map<String, dynamic> json) {
    return MissionBuilding(
      id: json['id'] as String,
      ebId: json['eb_id'] as String,
      buildingNumber: json['building_number'] as int,
      censusHouseCount: json['census_house_count'] as int,
      buildingType: json['building_type'] as String,
      mapX: (json['map_x'] as num).toDouble(),
      mapY: (json['map_y'] as num).toDouble(),
      status: json['status'] as String,
      notes: json['notes'] as String?,
      routeSequence: json['route_sequence'] as int?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toPlanJson() => {
        'buildingNumber': buildingNumber,
        'censusHouseCount': censusHouseCount,
        'buildingType': buildingType,
        'mapX': mapX,
        'mapY': mapY,
        if (routeSequence != null) 'routeSequence': routeSequence,
      };
}

class MissionLandmark {
  MissionLandmark({
    required this.name,
    required this.landmarkType,
    required this.mapX,
    required this.mapY,
  });

  final String name;
  final String landmarkType;
  final double mapX;
  final double mapY;

  Map<String, dynamic> toPlanJson() => {
        'name': name,
        'landmarkType': landmarkType,
        'mapX': mapX,
        'mapY': mapY,
      };
}

class MissionDashboard {
  const MissionDashboard({
    required this.ebId,
    required this.ebCode,
    required this.totalBuildings,
    required this.completedBuildings,
    required this.remainingBuildings,
    required this.progressPercent,
    required this.revisitRequired,
    this.nextBuilding,
    this.nextBuildingStrategy,
    this.layoutImageUrl,
  });

  final String ebId;
  final String ebCode;
  final int totalBuildings;
  final int completedBuildings;
  final int remainingBuildings;
  final double progressPercent;
  final int revisitRequired;
  final MissionBuilding? nextBuilding;
  final String? nextBuildingStrategy;
  final String? layoutImageUrl;

  factory MissionDashboard.fromJson(Map<String, dynamic> json) {
    return MissionDashboard(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      totalBuildings: json['totalBuildings'] as int,
      completedBuildings: json['completedBuildings'] as int,
      remainingBuildings: json['remainingBuildings'] as int,
      progressPercent: (json['progressPercent'] as num).toDouble(),
      revisitRequired: json['revisitRequired'] as int,
      nextBuilding: json['nextBuilding'] != null
          ? MissionBuilding.fromJson(json['nextBuilding'] as Map<String, dynamic>)
          : null,
      nextBuildingStrategy: json['nextBuildingStrategy'] as String?,
      layoutImageUrl: json['layoutImageUrl'] as String?,
    );
  }
}

class DiscoveryStatus {
  const DiscoveryStatus({
    required this.ebId,
    required this.ebCode,
    required this.phase,
    required this.boundaryCoveragePercent,
    required this.roadCoveragePercent,
    required this.pathWalkedMeters,
    required this.pathWalkedLabel,
    required this.walkingTimeMinutes,
    required this.walkingTimeLabel,
    required this.buildingsDiscovered,
    required this.landmarksDiscovered,
    required this.boundaryVertices,
    required this.boundaryClosed,
    required this.suggestedNextBuildingNumber,
    required this.suggestedNextLabel,
    required this.numberingIssues,
    required this.gapSummary,
    required this.zeroExclusionWarnings,
    required this.coverageGaps,
    this.hasOfficialBoundary = false,
    this.officialBoundaryAreaLabel,
    this.startPointDistanceLabel,
    this.startPointBearing,
    this.startPointReached = false,
    this.boundarySource,
  });

  final String ebId;
  final String ebCode;
  final String phase;
  final int boundaryCoveragePercent;
  final int roadCoveragePercent;
  final int pathWalkedMeters;
  final String pathWalkedLabel;
  final int walkingTimeMinutes;
  final String walkingTimeLabel;
  final int buildingsDiscovered;
  final int landmarksDiscovered;
  final int boundaryVertices;
  final bool boundaryClosed;
  final int suggestedNextBuildingNumber;
  final String suggestedNextLabel;
  final List<NumberingIssue> numberingIssues;
  final GapSummary gapSummary;
  final List<ZeroExclusionWarning> zeroExclusionWarnings;
  final List<CoverageGap> coverageGaps;
  final bool hasOfficialBoundary;
  final String? officialBoundaryAreaLabel;
  final String? startPointDistanceLabel;
  final double? startPointBearing;
  final bool startPointReached;
  final String? boundarySource;

  factory DiscoveryStatus.fromJson(Map<String, dynamic> json) {
    return DiscoveryStatus(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      phase: json['phase'] as String,
      boundaryCoveragePercent: json['boundaryCoveragePercent'] as int,
      roadCoveragePercent: (json['roadCoveragePercent'] as num?)?.toInt() ?? 0,
      pathWalkedMeters: json['pathWalkedMeters'] as int,
      pathWalkedLabel: json['pathWalkedLabel'] as String,
      walkingTimeMinutes: (json['walkingTimeMinutes'] as num?)?.toInt() ?? 0,
      walkingTimeLabel: json['walkingTimeLabel'] as String? ?? '—',
      buildingsDiscovered: json['buildingsDiscovered'] as int,
      landmarksDiscovered: json['landmarksDiscovered'] as int,
      boundaryVertices: json['boundaryVertices'] as int,
      boundaryClosed: json['boundaryClosed'] as bool,
      suggestedNextBuildingNumber: json['suggestedNextBuildingNumber'] as int,
      suggestedNextLabel: json['suggestedNextLabel'] as String? ?? 'CN-001',
      numberingIssues: (json['numberingIssues'] as List<dynamic>? ?? [])
          .map((e) => NumberingIssue.fromJson(e as Map<String, dynamic>))
          .toList(),
      gapSummary: GapSummary.fromJson(json['gapSummary'] as Map<String, dynamic>? ?? {
        'total': 0, 'open': 0, 'resolved': 0, 'highPriority': 0, 'mediumPriority': 0, 'lowPriority': 0,
      }),
      zeroExclusionWarnings: (json['zeroExclusionWarnings'] as List<dynamic>)
          .map((e) => ZeroExclusionWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverageGaps: (json['coverageGaps'] as List<dynamic>? ?? [])
          .map((e) => CoverageGap.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasOfficialBoundary: json['hasOfficialBoundary'] as bool? ?? false,
      officialBoundaryAreaLabel: json['officialBoundaryAreaLabel'] as String?,
      startPointDistanceLabel: json['startPointDistanceLabel'] as String?,
      startPointBearing: (json['startPointBearing'] as num?)?.toDouble(),
      startPointReached: json['startPointReached'] as bool? ?? false,
      boundarySource: json['boundarySource'] as String?,
    );
  }
}

class NumberingIssue {
  const NumberingIssue({
    required this.buildingId,
    required this.buildingNumber,
    required this.expectedNumber,
    required this.expectedLabel,
  });

  final String buildingId;
  final int buildingNumber;
  final int expectedNumber;
  final String expectedLabel;

  factory NumberingIssue.fromJson(Map<String, dynamic> json) {
    return NumberingIssue(
      buildingId: json['buildingId'] as String,
      buildingNumber: json['buildingNumber'] as int,
      expectedNumber: json['expectedNumber'] as int,
      expectedLabel: json['expectedLabel'] as String,
    );
  }
}

class GapSummary {
  const GapSummary({
    required this.total,
    required this.open,
    required this.resolved,
    required this.highPriority,
    required this.mediumPriority,
    required this.lowPriority,
  });

  final int total;
  final int open;
  final int resolved;
  final int highPriority;
  final int mediumPriority;
  final int lowPriority;

  factory GapSummary.fromJson(Map<String, dynamic> json) {
    return GapSummary(
      total: json['total'] as int,
      open: json['open'] as int,
      resolved: json['resolved'] as int,
      highPriority: json['highPriority'] as int,
      mediumPriority: json['mediumPriority'] as int,
      lowPriority: json['lowPriority'] as int,
    );
  }
}

class GapResolution {
  const GapResolution({required this.status, required this.resolvedAt, this.notes});

  final String status;
  final String resolvedAt;
  final String? notes;

  factory GapResolution.fromJson(Map<String, dynamic> json) {
    return GapResolution(
      status: json['status'] as String,
      resolvedAt: json['resolvedAt'] as String,
      notes: json['notes'] as String?,
    );
  }
}

class CoverageGap {
  const CoverageGap({
    required this.id,
    required this.type,
    required this.reason,
    required this.severity,
    required this.title,
    required this.description,
    this.latitude,
    this.longitude,
    this.mapX,
    this.mapY,
    this.distanceMeters,
    this.bearingDegrees,
    this.distanceLabel,
    this.resolution,
  });

  final String id;
  final String type;
  final String reason;
  final String severity;
  final String title;
  final String description;
  final double? latitude;
  final double? longitude;
  final double? mapX;
  final double? mapY;
  final double? distanceMeters;
  final double? bearingDegrees;
  final String? distanceLabel;
  final GapResolution? resolution;

  bool get isResolved => resolution != null;
  bool get isNavigable => latitude != null && longitude != null;

  factory CoverageGap.fromJson(Map<String, dynamic> json) {
    return CoverageGap(
      id: json['id'] as String? ?? '',
      type: json['type'] as String,
      reason: json['reason'] as String? ?? json['type'] as String,
      severity: json['severity'] as String? ?? 'medium',
      title: json['title'] as String? ?? json['description'] as String,
      description: json['description'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      mapX: (json['mapX'] as num?)?.toDouble(),
      mapY: (json['mapY'] as num?)?.toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      bearingDegrees: (json['bearingDegrees'] as num?)?.toDouble(),
      distanceLabel: json['distanceLabel'] as String?,
      resolution: json['resolution'] != null
          ? GapResolution.fromJson(json['resolution'] as Map<String, dynamic>)
          : null,
    );
  }
}

class CoverageGapsResponse {
  const CoverageGapsResponse({
    required this.ebId,
    required this.ebCode,
    required this.summary,
    required this.gaps,
  });

  final String ebId;
  final String ebCode;
  final GapSummary summary;
  final List<CoverageGap> gaps;

  factory CoverageGapsResponse.fromJson(Map<String, dynamic> json) {
    return CoverageGapsResponse(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      summary: GapSummary.fromJson(json['summary'] as Map<String, dynamic>),
      gaps: (json['gaps'] as List<dynamic>)
          .map((e) => CoverageGap.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ZeroExclusionWarning {
  const ZeroExclusionWarning({
    required this.reason,
    required this.description,
    this.severity = 'medium',
  });

  final String reason;
  final String description;
  final String severity;

  factory ZeroExclusionWarning.fromJson(Map<String, dynamic> json) {
    return ZeroExclusionWarning(
      reason: json['reason'] as String,
      description: json['description'] as String,
      severity: json['severity'] as String? ?? 'medium',
    );
  }
}

class DraftHlbMap {
  const DraftHlbMap({
    required this.ebId,
    required this.ebCode,
    required this.boundary,
    required this.boundaryClosed,
    required this.buildings,
    required this.landmarks,
    required this.walkPath,
    required this.serpentineOrder,
    this.lineFeatures = const [],
    this.serpentineArrows = const [],
    this.titleBlock,
    this.footerBlock = const DraftHlbFooterBlock(),
    this.annotations = const [],
    this.startPoint,
    this.endPoint,
    this.isOfficialBoundary = false,
  });

  final String ebId;
  final String ebCode;
  final List<MapPoint> boundary;
  final bool boundaryClosed;
  final List<DraftMapBuilding> buildings;
  final List<DraftMapLandmark> landmarks;
  final List<MapPoint> walkPath;
  final List<SerpentineEntry> serpentineOrder;
  final List<DraftMapLineFeature> lineFeatures;
  final List<SerpentineArrow> serpentineArrows;
  final DraftHlbTitleBlock? titleBlock;
  final DraftHlbFooterBlock footerBlock;
  final List<DraftMapAnnotation> annotations;
  final DraftMapEndpoint? startPoint;
  final DraftMapEndpoint? endPoint;
  final bool isOfficialBoundary;

  factory DraftHlbMap.fromJson(Map<String, dynamic> json) {
    return DraftHlbMap(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      boundary: (json['boundary'] as List<dynamic>? ?? [])
          .map((e) => MapPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      boundaryClosed: json['boundaryClosed'] as bool? ?? false,
      buildings: (json['buildings'] as List<dynamic>? ?? [])
          .map((e) => DraftMapBuilding.fromJson(e as Map<String, dynamic>))
          .toList(),
      landmarks: (json['landmarks'] as List<dynamic>? ?? [])
          .map((e) => DraftMapLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
      walkPath: (json['walkPath'] as List<dynamic>? ?? [])
          .map((e) => MapPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      serpentineOrder: (json['serpentineOrder'] as List<dynamic>? ?? [])
          .map((e) => SerpentineEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      lineFeatures: (json['lineFeatures'] as List<dynamic>? ?? [])
          .map((e) => DraftMapLineFeature.fromJson(e as Map<String, dynamic>))
          .toList(),
      serpentineArrows: (json['serpentineArrows'] as List<dynamic>? ?? [])
          .map((e) => SerpentineArrow.fromJson(e as Map<String, dynamic>))
          .toList(),
      titleBlock: json['titleBlock'] != null
          ? DraftHlbTitleBlock.fromJson(json['titleBlock'] as Map<String, dynamic>)
          : null,
      footerBlock: json['footerBlock'] != null
          ? DraftHlbFooterBlock.fromJson(json['footerBlock'] as Map<String, dynamic>)
          : const DraftHlbFooterBlock(),
      annotations: (json['annotations'] as List<dynamic>? ?? [])
          .map((e) => DraftMapAnnotation.fromJson(e as Map<String, dynamic>))
          .toList(),
      startPoint: json['startPoint'] != null
          ? DraftMapEndpoint.fromJson(json['startPoint'] as Map<String, dynamic>)
          : null,
      endPoint: json['endPoint'] != null
          ? DraftMapEndpoint.fromJson(json['endPoint'] as Map<String, dynamic>)
          : null,
      isOfficialBoundary: json['isOfficialBoundary'] as bool? ?? false,
    );
  }
}

class DraftMapBuilding {
  const DraftMapBuilding({
    required this.id,
    required this.buildingNumber,
    required this.censusHouseCount,
    required this.buildingType,
    required this.mapX,
    required this.mapY,
    required this.label,
  });

  final String id;
  final int buildingNumber;
  final int censusHouseCount;
  final String buildingType;
  final double mapX;
  final double mapY;
  final String label;

  factory DraftMapBuilding.fromJson(Map<String, dynamic> json) {
    return DraftMapBuilding(
      id: json['id'] as String,
      buildingNumber: json['buildingNumber'] as int,
      censusHouseCount: json['censusHouseCount'] as int,
      buildingType: json['buildingType'] as String,
      mapX: (json['mapX'] as num).toDouble(),
      mapY: (json['mapY'] as num).toDouble(),
      label: json['label'] as String,
    );
  }
}

class DraftMapLandmark {
  const DraftMapLandmark({
    required this.name,
    required this.type,
    required this.mapX,
    required this.mapY,
  });

  final String name;
  final String type;
  final double mapX;
  final double mapY;

  factory DraftMapLandmark.fromJson(Map<String, dynamic> json) {
    return DraftMapLandmark(
      name: json['name'] as String,
      type: json['type'] as String,
      mapX: (json['mapX'] as num).toDouble(),
      mapY: (json['mapY'] as num).toDouble(),
    );
  }
}

class SerpentineEntry {
  const SerpentineEntry({
    required this.buildingId,
    required this.sequence,
    required this.label,
  });

  final String buildingId;
  final int sequence;
  final String label;

  factory SerpentineEntry.fromJson(Map<String, dynamic> json) {
    return SerpentineEntry(
      buildingId: json['buildingId'] as String,
      sequence: json['sequence'] as int,
      label: json['label'] as String,
    );
  }
}

class DraftMapLineFeature {
  const DraftMapLineFeature({
    required this.id,
    required this.segmentType,
    required this.points,
    this.name,
    this.labelRotation = 0,
  });

  final String id;
  final String segmentType;
  final String? name;
  final List<MapPoint> points;
  final double labelRotation;

  factory DraftMapLineFeature.fromJson(Map<String, dynamic> json) {
    return DraftMapLineFeature(
      id: json['id'] as String,
      segmentType: json['segmentType'] as String? ?? 'pucca_road',
      name: json['name'] as String?,
      labelRotation: (json['labelRotation'] as num?)?.toDouble() ?? 0,
      points: (json['points'] as List<dynamic>? ?? [])
          .map((e) => MapPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SerpentineArrow {
  const SerpentineArrow({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.sequence,
  });

  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final int sequence;

  factory SerpentineArrow.fromJson(Map<String, dynamic> json) {
    return SerpentineArrow(
      fromX: (json['fromX'] as num).toDouble(),
      fromY: (json['fromY'] as num).toDouble(),
      toX: (json['toX'] as num).toDouble(),
      toY: (json['toY'] as num).toDouble(),
      sequence: json['sequence'] as int,
    );
  }
}

class DraftHlbTitleBlock {
  const DraftHlbTitleBlock({
    required this.ebCode,
    this.stateName,
    this.stateCode,
    this.district,
    this.districtCode,
    this.subDistrict,
    this.subDistrictCode,
    this.townVillage,
    this.townCode,
    this.wardNo,
    this.subBlockNo,
  });

  final String ebCode;
  final String? stateName;
  final String? stateCode;
  final String? district;
  final String? districtCode;
  final String? subDistrict;
  final String? subDistrictCode;
  final String? townVillage;
  final String? townCode;
  final String? wardNo;
  final String? subBlockNo;

  String _codeLabel(String? name, String? code) {
    if (name == null || name.isEmpty) return code ?? '';
    if (code == null || code.isEmpty) return name;
    return '$name (Code: $code)';
  }

  List<String> get lines {
    final out = <String>[];
    if (stateName != null && stateName!.isNotEmpty) {
      out.add('State/UT: ${_codeLabel(stateName, stateCode)}');
    }
    if (district != null && district!.isNotEmpty) {
      out.add('District: ${_codeLabel(district, districtCode)}');
    }
    if (subDistrict != null && subDistrict!.isNotEmpty) {
      out.add('Tehsil/Taluk/Block: ${_codeLabel(subDistrict, subDistrictCode)}');
    }
    if (townVillage != null && townVillage!.isNotEmpty) {
      out.add('Town/Village: ${_codeLabel(townVillage, townCode)}');
    }
    if (wardNo != null && wardNo!.isNotEmpty) out.add('Ward Code No.: $wardNo');
    final ebLine = subBlockNo != null && subBlockNo!.isNotEmpty
        ? 'EB No. $ebCode  ·  Sub-Block No. $subBlockNo'
        : 'Enumeration Block No.: $ebCode';
    out.add(ebLine);
    return out;
  }

  factory DraftHlbTitleBlock.fromJson(Map<String, dynamic> json) {
    return DraftHlbTitleBlock(
      ebCode: json['ebCode'] as String,
      stateName: json['stateName'] as String?,
      stateCode: json['stateCode'] as String?,
      district: json['district'] as String?,
      districtCode: json['districtCode'] as String?,
      subDistrict: json['subDistrict'] as String?,
      subDistrictCode: json['subDistrictCode'] as String?,
      townVillage: json['townVillage'] as String?,
      townCode: json['townCode'] as String?,
      wardNo: json['wardNo'] as String?,
      subBlockNo: json['subBlockNo'] as String?,
    );
  }
}

class DraftHlbFooterBlock {
  const DraftHlbFooterBlock({
    this.enumeratorName,
    this.enumeratorDate,
    this.supervisorName,
    this.supervisorDate,
  });

  final String? enumeratorName;
  final String? enumeratorDate;
  final String? supervisorName;
  final String? supervisorDate;

  factory DraftHlbFooterBlock.fromJson(Map<String, dynamic> json) => DraftHlbFooterBlock(
        enumeratorName: json['enumeratorName'] as String?,
        enumeratorDate: json['enumeratorDate'] as String?,
        supervisorName: json['supervisorName'] as String?,
        supervisorDate: json['supervisorDate'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (enumeratorName != null) 'enumeratorName': enumeratorName,
        if (enumeratorDate != null) 'enumeratorDate': enumeratorDate,
        if (supervisorName != null) 'supervisorName': supervisorName,
        if (supervisorDate != null) 'supervisorDate': supervisorDate,
      };
}

class DraftMapAnnotation {
  const DraftMapAnnotation({
    required this.text,
    required this.annotationType,
    required this.mapX,
    required this.mapY,
    this.rotationDegrees = 0,
  });

  final String text;
  final String annotationType;
  final double mapX;
  final double mapY;
  final double rotationDegrees;

  factory DraftMapAnnotation.fromJson(Map<String, dynamic> json) => DraftMapAnnotation(
        text: json['text'] as String,
        annotationType: json['annotationType'] as String? ?? 'custom',
        mapX: (json['mapX'] as num).toDouble(),
        mapY: (json['mapY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
      );
}

class DraftMapEndpoint {
  const DraftMapEndpoint({
    required this.label,
    required this.mapX,
    required this.mapY,
    this.buildingNumber,
  });

  final String label;
  final double mapX;
  final double mapY;
  final int? buildingNumber;

  factory DraftMapEndpoint.fromJson(Map<String, dynamic> json) => DraftMapEndpoint(
        label: json['label'] as String,
        mapX: (json['mapX'] as num).toDouble(),
        mapY: (json['mapY'] as num).toDouble(),
        buildingNumber: json['buildingNumber'] as int?,
      );
}

class ZeroExclusionValidation {
  const ZeroExclusionValidation({
    required this.canFinalize,
    required this.warnings,
    required this.coverageGaps,
    required this.numberingIssues,
    this.gapSummary,
    this.ignoredSuggestionsCount = 0,
  });

  final bool canFinalize;
  final List<ZeroExclusionWarning> warnings;
  final List<CoverageGap> coverageGaps;
  final List<NumberingIssue> numberingIssues;
  final GapSummary? gapSummary;
  final int ignoredSuggestionsCount;

  factory ZeroExclusionValidation.fromJson(Map<String, dynamic> json) {
    return ZeroExclusionValidation(
      canFinalize: json['canFinalize'] as bool,
      warnings: (json['warnings'] as List<dynamic>)
          .map((e) => ZeroExclusionWarning.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverageGaps: (json['coverageGaps'] as List<dynamic>)
          .map((e) => CoverageGap.fromJson(e as Map<String, dynamic>))
          .toList(),
      numberingIssues: (json['numberingIssues'] as List<dynamic>)
          .map((e) => NumberingIssue.fromJson(e as Map<String, dynamic>))
          .toList(),
      gapSummary: json['gapSummary'] != null
          ? GapSummary.fromJson(json['gapSummary'] as Map<String, dynamic>)
          : null,
      ignoredSuggestionsCount: json['ignoredSuggestionsCount'] as int? ?? 0,
    );
  }
}

class DayReview {
  const DayReview({
    required this.ebId,
    required this.ebCode,
    required this.progressPercent,
    required this.completedBuildings,
    required this.remainingBuildings,
    required this.remainingBuildingNumbers,
    required this.estimatedRemainingMinutes,
    required this.avgMinutesPerBuilding,
  });

  final String ebId;
  final String ebCode;
  final double progressPercent;
  final int completedBuildings;
  final int remainingBuildings;
  final List<int> remainingBuildingNumbers;
  final int estimatedRemainingMinutes;
  final int avgMinutesPerBuilding;

  factory DayReview.fromJson(Map<String, dynamic> json) {
    return DayReview(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      progressPercent: (json['progressPercent'] as num).toDouble(),
      completedBuildings: json['completedBuildings'] as int,
      remainingBuildings: json['remainingBuildings'] as int,
      remainingBuildingNumbers: (json['remainingBuildingNumbers'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
      estimatedRemainingMinutes: json['estimatedRemainingMinutes'] as int,
      avgMinutesPerBuilding: json['avgMinutesPerBuilding'] as int,
    );
  }
}

String buildingStatusToApi(MissionBuildingStatus s) {
  switch (s) {
    case MissionBuildingStatus.visited:
      return 'visited';
    case MissionBuildingStatus.completed:
      return 'completed';
    case MissionBuildingStatus.revisitRequired:
      return 'revisit_required';
    case MissionBuildingStatus.notVisited:
      return 'not_visited';
  }
}

Color missionStatusColor(String status) {
  switch (status) {
    case 'completed':
      return const Color(0xFF4CAF50);
    case 'visited':
      return const Color(0xFFFFC107);
    case 'revisit_required':
      return const Color(0xFFF44336);
    default:
      return const Color(0xFF9E9E9E);
  }
}
