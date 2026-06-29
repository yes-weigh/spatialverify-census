/// Full on-device HLB state — source of truth when offline.
class HlbLocalState {
  HlbLocalState({
    required this.ebId,
    required this.ebCode,
    required this.projectId,
    this.blockStatus = 'draft',
    this.phase = 'mapping',
    this.boundaryVertices = const [],
    this.buildings = const [],
    this.landmarks = const [],
    this.breadcrumbs = const [],
    this.gapResolutions = const [],
    this.spatialNodes = const [],
    this.roadSegments = const [],
    this.mapAnnotations = const [],
    this.ignoredSuggestions = const [],
    this.officialBoundary,
    this.boundaryAudit,
    this.layoutGeoref,
    this.missionIntelligence,
    DateTime? updatedAt,
    this.serverSyncedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String ebId;
  final String ebCode;
  final String projectId;
  final String blockStatus;
  final String phase;
  final List<LocalBoundaryVertex> boundaryVertices;
  final List<LocalBuilding> buildings;
  final List<LocalLandmark> landmarks;
  final List<LocalBreadcrumb> breadcrumbs;
  final List<LocalGapResolution> gapResolutions;
  final List<LocalSpatialNode> spatialNodes;
  final List<LocalRoadSegment> roadSegments;
  final List<LocalMapAnnotation> mapAnnotations;
  final List<LocalIgnoredSuggestion> ignoredSuggestions;
  final LocalOfficialBoundary? officialBoundary;
  final LocalBoundaryAudit? boundaryAudit;
  final Map<String, dynamic>? layoutGeoref;
  final Map<String, dynamic>? missionIntelligence;
  final DateTime updatedAt;
  final DateTime? serverSyncedAt;

  HlbLocalState copyWith({
    String? ebCode,
    String? blockStatus,
    String? phase,
    List<LocalBoundaryVertex>? boundaryVertices,
    List<LocalBuilding>? buildings,
    List<LocalLandmark>? landmarks,
    List<LocalBreadcrumb>? breadcrumbs,
    List<LocalGapResolution>? gapResolutions,
    List<LocalSpatialNode>? spatialNodes,
    List<LocalRoadSegment>? roadSegments,
    List<LocalMapAnnotation>? mapAnnotations,
    List<LocalIgnoredSuggestion>? ignoredSuggestions,
    LocalOfficialBoundary? officialBoundary,
    LocalBoundaryAudit? boundaryAudit,
    Map<String, dynamic>? layoutGeoref,
    Map<String, dynamic>? missionIntelligence,
    bool clearOfficialBoundary = false,
    bool clearBoundaryAudit = false,
    DateTime? updatedAt,
    DateTime? serverSyncedAt,
  }) {
    return HlbLocalState(
      ebId: ebId,
      ebCode: ebCode ?? this.ebCode,
      projectId: projectId,
      blockStatus: blockStatus ?? this.blockStatus,
      phase: phase ?? this.phase,
      boundaryVertices: boundaryVertices ?? this.boundaryVertices,
      buildings: buildings ?? this.buildings,
      landmarks: landmarks ?? this.landmarks,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      gapResolutions: gapResolutions ?? this.gapResolutions,
      spatialNodes: spatialNodes ?? this.spatialNodes,
      roadSegments: roadSegments ?? this.roadSegments,
      mapAnnotations: mapAnnotations ?? this.mapAnnotations,
      ignoredSuggestions: ignoredSuggestions ?? this.ignoredSuggestions,
      officialBoundary: clearOfficialBoundary ? null : (officialBoundary ?? this.officialBoundary),
      boundaryAudit: clearBoundaryAudit ? null : (boundaryAudit ?? this.boundaryAudit),
      layoutGeoref: layoutGeoref ?? this.layoutGeoref,
      missionIntelligence: missionIntelligence ?? this.missionIntelligence,
      updatedAt: updatedAt ?? DateTime.now(),
      serverSyncedAt: serverSyncedAt ?? this.serverSyncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'ebId': ebId,
        'ebCode': ebCode,
        'projectId': projectId,
        'blockStatus': blockStatus,
        'phase': phase,
        'boundaryVertices': boundaryVertices.map((e) => e.toJson()).toList(),
        'buildings': buildings.map((e) => e.toJson()).toList(),
        'landmarks': landmarks.map((e) => e.toJson()).toList(),
        'breadcrumbs': breadcrumbs.map((e) => e.toJson()).toList(),
        'gapResolutions': gapResolutions.map((e) => e.toJson()).toList(),
        'spatialNodes': spatialNodes.map((e) => e.toJson()).toList(),
        'roadSegments': roadSegments.map((e) => e.toJson()).toList(),
        'mapAnnotations': mapAnnotations.map((e) => e.toJson()).toList(),
        'ignoredSuggestions': ignoredSuggestions.map((e) => e.toJson()).toList(),
        'officialBoundary': officialBoundary?.toJson(),
        'boundaryAudit': boundaryAudit?.toJson(),
        'layoutGeoref': layoutGeoref,
        'missionIntelligence': missionIntelligence,
        'updatedAt': updatedAt.toIso8601String(),
        'serverSyncedAt': serverSyncedAt?.toIso8601String(),
      };

  factory HlbLocalState.fromJson(Map<String, dynamic> json) {
    return HlbLocalState(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      projectId: json['projectId'] as String,
      blockStatus: json['blockStatus'] as String? ?? 'draft',
      phase: json['phase'] as String? ?? 'mapping',
      boundaryVertices: (json['boundaryVertices'] as List<dynamic>? ?? [])
          .map((e) => LocalBoundaryVertex.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      buildings: (json['buildings'] as List<dynamic>? ?? [])
          .map((e) => LocalBuilding.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      landmarks: (json['landmarks'] as List<dynamic>? ?? [])
          .map((e) => LocalLandmark.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      breadcrumbs: (json['breadcrumbs'] as List<dynamic>? ?? [])
          .map((e) => LocalBreadcrumb.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      gapResolutions: (json['gapResolutions'] as List<dynamic>? ?? [])
          .map((e) => LocalGapResolution.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      spatialNodes: (json['spatialNodes'] as List<dynamic>? ?? [])
          .map((e) => LocalSpatialNode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      roadSegments: (json['roadSegments'] as List<dynamic>? ?? [])
          .map((e) => LocalRoadSegment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      mapAnnotations: (json['mapAnnotations'] as List<dynamic>? ?? [])
          .map((e) => LocalMapAnnotation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      ignoredSuggestions: (json['ignoredSuggestions'] as List<dynamic>? ?? [])
          .map((e) => LocalIgnoredSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      officialBoundary: json['officialBoundary'] != null
          ? LocalOfficialBoundary.fromJson(Map<String, dynamic>.from(json['officialBoundary'] as Map))
          : null,
      boundaryAudit: json['boundaryAudit'] != null
          ? LocalBoundaryAudit.fromJson(Map<String, dynamic>.from(json['boundaryAudit'] as Map))
          : null,
      layoutGeoref: json['layoutGeoref'] != null
          ? Map<String, dynamic>.from(json['layoutGeoref'] as Map)
          : null,
      missionIntelligence: json['missionIntelligence'] != null
          ? Map<String, dynamic>.from(json['missionIntelligence'] as Map)
          : null,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      serverSyncedAt: json['serverSyncedAt'] != null
          ? DateTime.tryParse(json['serverSyncedAt'] as String)
          : null,
    );
  }

  factory HlbLocalState.fromServerSnapshot(Map<String, dynamic> json) {
    return HlbLocalState(
      ebId: json['ebId'] as String,
      ebCode: json['ebCode'] as String,
      projectId: json['projectId'] as String,
      blockStatus: json['blockStatus'] as String? ?? 'draft',
      phase: json['phase'] as String? ?? 'mapping',
      boundaryVertices: (json['boundaryVertices'] as List<dynamic>? ?? [])
          .map((e) => LocalBoundaryVertex.fromServer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      buildings: (json['buildings'] as List<dynamic>? ?? [])
          .map((e) => LocalBuilding.fromServer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      landmarks: (json['landmarks'] as List<dynamic>? ?? [])
          .map((e) => LocalLandmark.fromServer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      breadcrumbs: (json['breadcrumbs'] as List<dynamic>? ?? [])
          .map((e) => LocalBreadcrumb.fromServer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      gapResolutions: (json['gapResolutions'] as List<dynamic>? ?? [])
          .map((e) => LocalGapResolution.fromServer(Map<String, dynamic>.from(e as Map)))
          .toList(),
      officialBoundary: json['officialBoundary'] != null
          ? LocalOfficialBoundary.fromServer(Map<String, dynamic>.from(json['officialBoundary'] as Map))
          : null,
      boundaryAudit: json['boundaryAudit'] != null
          ? LocalBoundaryAudit.fromJson(Map<String, dynamic>.from(json['boundaryAudit'] as Map))
          : null,
      layoutGeoref: json['layoutGeoref'] != null
          ? Map<String, dynamic>.from(json['layoutGeoref'] as Map)
          : null,
      missionIntelligence: () {
        final lg = json['layoutGeoref'] as Map<String, dynamic>?;
        final mi = lg?['missionIntelligence'];
        if (mi != null) return Map<String, dynamic>.from(mi as Map);
        return null;
      }(),
      serverSyncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
    );
  }

  bool get hasOfficialBoundary => officialBoundary != null;

  List<({double lat, double lng})> get officialBoundaryRing =>
      officialBoundary?.ringLatLng ?? const [];
}

class LocalBoundaryVertex {
  LocalBoundaryVertex({
    required this.localId,
    this.serverId,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  final String localId;
  final String? serverId;
  final int sequence;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'serverId': serverId,
        'sequence': sequence,
        'latitude': latitude,
        'longitude': longitude,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory LocalBoundaryVertex.fromJson(Map<String, dynamic> json) => LocalBoundaryVertex(
        localId: json['localId'] as String,
        serverId: json['serverId'] as String?,
        sequence: json['sequence'] as int,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );

  factory LocalBoundaryVertex.fromServer(Map<String, dynamic> json) => LocalBoundaryVertex(
        localId: json['id'] as String,
        serverId: json['id'] as String,
        sequence: json['sequence'] as int,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );
}

class LocalBuilding {
  LocalBuilding({
    required this.localId,
    this.serverId,
    required this.buildingNumber,
    required this.censusHouseCount,
    required this.buildingType,
    required this.latitude,
    required this.longitude,
    required this.mapX,
    required this.mapY,
  });

  final String localId;
  final String? serverId;
  final int buildingNumber;
  final int censusHouseCount;
  final String buildingType;
  final double latitude;
  final double longitude;
  final double mapX;
  final double mapY;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'serverId': serverId,
        'buildingNumber': buildingNumber,
        'censusHouseCount': censusHouseCount,
        'buildingType': buildingType,
        'latitude': latitude,
        'longitude': longitude,
        'mapX': mapX,
        'mapY': mapY,
      };

  factory LocalBuilding.fromJson(Map<String, dynamic> json) => LocalBuilding(
        localId: json['localId'] as String,
        serverId: json['serverId'] as String?,
        buildingNumber: json['buildingNumber'] as int,
        censusHouseCount: json['censusHouseCount'] as int,
        buildingType: json['buildingType'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        mapX: (json['mapX'] as num).toDouble(),
        mapY: (json['mapY'] as num).toDouble(),
      );

  factory LocalBuilding.fromServer(Map<String, dynamic> json) => LocalBuilding(
        localId: json['id'] as String,
        serverId: json['id'] as String,
        buildingNumber: json['buildingNumber'] as int,
        censusHouseCount: json['censusHouseCount'] as int,
        buildingType: json['buildingType'] as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        mapX: (json['mapX'] as num?)?.toDouble() ?? 0.5,
        mapY: (json['mapY'] as num?)?.toDouble() ?? 0.5,
      );
}

class LocalLandmark {
  LocalLandmark({
    required this.localId,
    this.serverId,
    required this.name,
    required this.landmarkType,
    required this.latitude,
    required this.longitude,
    required this.mapX,
    required this.mapY,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String landmarkType;
  final double latitude;
  final double longitude;
  final double mapX;
  final double mapY;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'serverId': serverId,
        'name': name,
        'landmarkType': landmarkType,
        'latitude': latitude,
        'longitude': longitude,
        'mapX': mapX,
        'mapY': mapY,
      };

  factory LocalLandmark.fromJson(Map<String, dynamic> json) => LocalLandmark(
        localId: json['localId'] as String,
        serverId: json['serverId'] as String?,
        name: json['name'] as String,
        landmarkType: json['landmarkType'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        mapX: (json['mapX'] as num).toDouble(),
        mapY: (json['mapY'] as num).toDouble(),
      );

  factory LocalLandmark.fromServer(Map<String, dynamic> json) => LocalLandmark(
        localId: json['id'] as String,
        serverId: json['id'] as String,
        name: json['name'] as String,
        landmarkType: json['landmarkType'] as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        mapX: (json['mapX'] as num?)?.toDouble() ?? 0.5,
        mapY: (json['mapY'] as num?)?.toDouble() ?? 0.5,
      );
}

class LocalBreadcrumb {
  LocalBreadcrumb({
    required this.localId,
    this.serverId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  final String localId;
  final String? serverId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'serverId': serverId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory LocalBreadcrumb.fromJson(Map<String, dynamic> json) => LocalBreadcrumb(
        localId: json['localId'] as String,
        serverId: json['serverId'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );

  factory LocalBreadcrumb.fromServer(Map<String, dynamic> json) => LocalBreadcrumb(
        localId: json['id'] as String,
        serverId: json['id'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );
}

class LocalGapResolution {
  LocalGapResolution({
    required this.gapFingerprint,
    required this.gapType,
    required this.gapReason,
    required this.resolution,
    this.notes,
    this.latitude,
    this.longitude,
    DateTime? resolvedAt,
  }) : resolvedAt = resolvedAt ?? DateTime.now();

  final String gapFingerprint;
  final String gapType;
  final String gapReason;
  final String resolution;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final DateTime resolvedAt;

  Map<String, dynamic> toJson() => {
        'gapFingerprint': gapFingerprint,
        'gapType': gapType,
        'gapReason': gapReason,
        'resolution': resolution,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'resolvedAt': resolvedAt.toIso8601String(),
      };

  factory LocalGapResolution.fromJson(Map<String, dynamic> json) => LocalGapResolution(
        gapFingerprint: json['gapFingerprint'] as String,
        gapType: json['gapType'] as String,
        gapReason: json['gapReason'] as String,
        resolution: json['resolution'] as String,
        notes: json['notes'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        resolvedAt: DateTime.tryParse(json['resolvedAt'] as String? ?? ''),
      );

  factory LocalGapResolution.fromServer(Map<String, dynamic> json) => LocalGapResolution(
        gapFingerprint: json['gapFingerprint'] as String,
        gapType: json['gapType'] as String,
        gapReason: json['gapReason'] as String,
        resolution: json['resolution'] as String,
        notes: json['notes'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        resolvedAt: DateTime.tryParse(json['resolvedAt'] as String? ?? ''),
      );
}

class LocalSpatialNode {
  LocalSpatialNode({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.photoPath,
    this.linkedEntityId,
    this.label,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final String type;
  final double latitude;
  final double longitude;
  final double? heading;
  final String? photoPath;
  final String? linkedEntityId;
  final String? label;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
        'heading': heading,
        'photoPath': photoPath,
        'linkedEntityId': linkedEntityId,
        'label': label,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LocalSpatialNode.fromJson(Map<String, dynamic> json) => LocalSpatialNode(
        id: json['id'] as String,
        type: json['type'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        photoPath: json['photoPath'] as String?,
        linkedEntityId: json['linkedEntityId'] as String?,
        label: json['label'] as String?,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      );
}

class LocalMapAnnotation {
  LocalMapAnnotation({
    required this.localId,
    required this.text,
    required this.annotationType,
    required this.latitude,
    required this.longitude,
    required this.mapX,
    required this.mapY,
    this.rotationDegrees = 0,
  });

  final String localId;
  final String text;
  /// road_name | area_name | adjacent_hlb | custom
  final String annotationType;
  final double latitude;
  final double longitude;
  final double mapX;
  final double mapY;
  final double rotationDegrees;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'text': text,
        'annotationType': annotationType,
        'latitude': latitude,
        'longitude': longitude,
        'mapX': mapX,
        'mapY': mapY,
        'rotationDegrees': rotationDegrees,
      };

  factory LocalMapAnnotation.fromJson(Map<String, dynamic> json) => LocalMapAnnotation(
        localId: json['localId'] as String,
        text: json['text'] as String,
        annotationType: json['annotationType'] as String? ?? 'custom',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        mapX: (json['mapX'] as num).toDouble(),
        mapY: (json['mapY'] as num).toDouble(),
        rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
      );
}

class LocalRoadSegment {
  LocalRoadSegment({
    required this.localId,
    required this.points,
    this.segmentType = 'pucca_road',
    this.name,
  });

  final String localId;
  final List<({double lat, double lng})> points;
  final String segmentType;
  final String? name;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'points': points.map((p) => {'lat': p.lat, 'lng': p.lng}).toList(),
        'segmentType': segmentType,
        if (name != null && name!.isNotEmpty) 'name': name,
      };

  factory LocalRoadSegment.fromJson(Map<String, dynamic> json) => LocalRoadSegment(
        localId: json['localId'] as String,
        points: (json['points'] as List<dynamic>)
            .map((p) => (lat: (p['lat'] as num).toDouble(), lng: (p['lng'] as num).toDouble()))
            .toList(),
        segmentType: () {
          final t = json['segmentType'] as String? ?? 'pucca_road';
          return t == 'road' ? 'pucca_road' : t;
        }(),
        name: json['name'] as String?,
      );
}

class LocalIgnoredSuggestion {
  LocalIgnoredSuggestion({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.timesIgnored = 1,
    DateTime? ignoredAt,
  }) : ignoredAt = ignoredAt ?? DateTime.now();

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final int timesIgnored;
  final DateTime ignoredAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'timesIgnored': timesIgnored,
        'ignoredAt': ignoredAt.toIso8601String(),
      };

  factory LocalIgnoredSuggestion.fromJson(Map<String, dynamic> json) => LocalIgnoredSuggestion(
        id: json['id'] as String,
        label: json['label'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timesIgnored: json['timesIgnored'] as int? ?? 1,
        ignoredAt: DateTime.tryParse(json['ignoredAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class LocalOfficialBoundary {
  LocalOfficialBoundary({
    required this.id,
    required this.hlbCode,
    this.name,
    required this.boundaryPolygon,
    required this.areaSqMeters,
    required this.startLat,
    required this.startLng,
    this.northDescription,
    this.southDescription,
    this.eastDescription,
    this.westDescription,
    this.source = 'official',
    DateTime? importedAt,
  }) : importedAt = importedAt ?? DateTime.now();

  final String id;
  final String hlbCode;
  final String? name;
  final Map<String, dynamic> boundaryPolygon;
  final double areaSqMeters;
  final double startLat;
  final double startLng;
  final String? northDescription;
  final String? southDescription;
  final String? eastDescription;
  final String? westDescription;
  final String source;
  final DateTime importedAt;

  List<({double lat, double lng})> get ringLatLng {
    final coords = boundaryPolygon['coordinates'] as List<dynamic>?;
    if (coords == null || coords.isEmpty) return [];
    final ring = coords.first as List<dynamic>;
    return ring.map((p) {
      final pair = p as List<dynamic>;
      return (lat: (pair[1] as num).toDouble(), lng: (pair[0] as num).toDouble());
    }).toList();
  }

  String get areaLabel {
    if (areaSqMeters >= 1000000) return '${(areaSqMeters / 1000000).toStringAsFixed(2)} km²';
    return '${(areaSqMeters / 10000).toStringAsFixed(2)} ha';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hlbCode': hlbCode,
        'name': name,
        'boundaryPolygon': boundaryPolygon,
        'areaSqMeters': areaSqMeters,
        'startLat': startLat,
        'startLng': startLng,
        'northDescription': northDescription,
        'southDescription': southDescription,
        'eastDescription': eastDescription,
        'westDescription': westDescription,
        'source': source,
        'importedAt': importedAt.toIso8601String(),
      };

  factory LocalOfficialBoundary.fromJson(Map<String, dynamic> json) => LocalOfficialBoundary(
        id: json['id'] as String,
        hlbCode: json['hlbCode'] as String,
        name: json['name'] as String?,
        boundaryPolygon: Map<String, dynamic>.from(json['boundaryPolygon'] as Map),
        areaSqMeters: (json['areaSqMeters'] as num).toDouble(),
        startLat: (json['startLat'] as num).toDouble(),
        startLng: (json['startLng'] as num).toDouble(),
        northDescription: json['northDescription'] as String?,
        southDescription: json['southDescription'] as String?,
        eastDescription: json['eastDescription'] as String?,
        westDescription: json['westDescription'] as String?,
        source: json['source'] as String? ?? 'official',
        importedAt: DateTime.tryParse(json['importedAt'] as String? ?? ''),
      );

  factory LocalOfficialBoundary.fromServer(Map<String, dynamic> json) {
    final start = json['startPoint'] as Map<String, dynamic>?;
    return LocalOfficialBoundary(
      id: json['id'] as String,
      hlbCode: json['hlbCode'] as String,
      name: json['name'] as String?,
      boundaryPolygon: Map<String, dynamic>.from(json['boundaryPolygon'] as Map),
      areaSqMeters: (json['areaSqMeters'] as num).toDouble(),
      startLat: (start?['lat'] as num?)?.toDouble() ?? (json['startLat'] as num?)?.toDouble() ?? 0,
      startLng: (start?['lng'] as num?)?.toDouble() ?? (json['startLng'] as num?)?.toDouble() ?? 0,
      northDescription: json['northDescription'] as String?,
      southDescription: json['southDescription'] as String?,
      eastDescription: json['eastDescription'] as String?,
      westDescription: json['westDescription'] as String?,
      importedAt: DateTime.tryParse(json['importedAt'] as String? ?? ''),
    );
  }
}

class LocalBoundaryAudit {
  LocalBoundaryAudit({
    this.enteredBoundaryAt,
    this.leftBoundaryAt,
    this.startPointReachedAt,
    this.discoveryStartedAt,
    this.outsideBoundaryDiscoveries = const [],
  });

  final DateTime? enteredBoundaryAt;
  final DateTime? leftBoundaryAt;
  final DateTime? startPointReachedAt;
  final DateTime? discoveryStartedAt;
  final List<LocalOutsideDiscovery> outsideBoundaryDiscoveries;

  Map<String, dynamic> toJson() => {
        'enteredBoundaryAt': enteredBoundaryAt?.toIso8601String(),
        'leftBoundaryAt': leftBoundaryAt?.toIso8601String(),
        'startPointReachedAt': startPointReachedAt?.toIso8601String(),
        'discoveryStartedAt': discoveryStartedAt?.toIso8601String(),
        'outsideBoundaryDiscoveries': outsideBoundaryDiscoveries.map((e) => e.toJson()).toList(),
      };

  factory LocalBoundaryAudit.fromJson(Map<String, dynamic> json) => LocalBoundaryAudit(
        enteredBoundaryAt: DateTime.tryParse(json['enteredBoundaryAt'] as String? ?? ''),
        leftBoundaryAt: DateTime.tryParse(json['leftBoundaryAt'] as String? ?? ''),
        startPointReachedAt: DateTime.tryParse(json['startPointReachedAt'] as String? ?? ''),
        discoveryStartedAt: DateTime.tryParse(json['discoveryStartedAt'] as String? ?? ''),
        outsideBoundaryDiscoveries: (json['outsideBoundaryDiscoveries'] as List<dynamic>? ?? [])
            .map((e) => LocalOutsideDiscovery.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  LocalBoundaryAudit copyWith({
    DateTime? enteredBoundaryAt,
    DateTime? leftBoundaryAt,
    DateTime? startPointReachedAt,
    DateTime? discoveryStartedAt,
    List<LocalOutsideDiscovery>? outsideBoundaryDiscoveries,
  }) {
    return LocalBoundaryAudit(
      enteredBoundaryAt: enteredBoundaryAt ?? this.enteredBoundaryAt,
      leftBoundaryAt: leftBoundaryAt ?? this.leftBoundaryAt,
      startPointReachedAt: startPointReachedAt ?? this.startPointReachedAt,
      discoveryStartedAt: discoveryStartedAt ?? this.discoveryStartedAt,
      outsideBoundaryDiscoveries: outsideBoundaryDiscoveries ?? this.outsideBoundaryDiscoveries,
    );
  }
}

class LocalOutsideDiscovery {
  LocalOutsideDiscovery({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.overridden,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  final double latitude;
  final double longitude;
  final String label;
  final bool overridden;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'label': label,
        'overridden': overridden,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory LocalOutsideDiscovery.fromJson(Map<String, dynamic> json) => LocalOutsideDiscovery(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        label: json['label'] as String,
        overridden: json['overridden'] as bool? ?? false,
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? ''),
      );
}
