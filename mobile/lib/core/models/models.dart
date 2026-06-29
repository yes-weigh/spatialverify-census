enum UserRole { admin, supervisor, fieldWorker }

enum AssetStatus { notSurveyed, pending, verified, rejected }

enum SyncStatus { pending, uploading, synced, failed, conflict }

enum HumanDecision { confirmed, rejected, edited }

class User {
  const User({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
  });

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final UserRole role;

  String get fullName => '$firstName $lastName';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['firstName'] as String? ?? json['first_name'] as String,
      lastName: json['lastName'] as String? ?? json['last_name'] as String,
      role: _parseRole(json['role'] as String),
    );
  }

  static UserRole _parseRole(String role) {
    switch (role) {
      case 'admin':
        return UserRole.admin;
      case 'supervisor':
        return UserRole.supervisor;
      default:
        return UserRole.fieldWorker;
    }
  }
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: json['expiresIn'] as int,
    );
  }
}

class Project {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.boundary,
    this.surveyRules = const {},
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? description;
  final Map<String, dynamic>? boundary;
  final Map<String, dynamic> surveyRules;
  final bool isActive;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      boundary: json['boundary'] as Map<String, dynamic>?,
      surveyRules: json['survey_rules'] as Map<String, dynamic>? ?? {},
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class Asset {
  const Asset({
    required this.id,
    required this.projectId,
    required this.name,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.categoryId,
    this.altitude,
    this.heading,
    this.clientId,
    this.version = 1,
  });

  final String id;
  final String projectId;
  final String? categoryId;
  final String name;
  final AssetStatus status;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? heading;
  final String? clientId;
  final int version;

  factory Asset.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    final coords = location?['coordinates'] as List<dynamic>?;
    return Asset(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      status: _parseStatus(json['status'] as String),
      latitude: coords != null ? (coords[1] as num).toDouble() : 0,
      longitude: coords != null ? (coords[0] as num).toDouble() : 0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      clientId: json['client_id'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }

  static AssetStatus _parseStatus(String status) {
    switch (status) {
      case 'verified':
        return AssetStatus.verified;
      case 'pending':
        return AssetStatus.pending;
      case 'rejected':
        return AssetStatus.rejected;
      default:
        return AssetStatus.notSurveyed;
    }
  }

  String get statusString {
    switch (status) {
      case AssetStatus.verified:
        return 'verified';
      case AssetStatus.pending:
        return 'pending';
      case AssetStatus.rejected:
        return 'rejected';
      case AssetStatus.notSurveyed:
        return 'not_surveyed';
    }
  }
}

class Detection {
  const Detection({
    required this.id,
    required this.categoryLabel,
    required this.confidence,
    required this.boundingBox,
    this.latitude,
    this.longitude,
    this.altitude,
    this.heading,
    this.clientId,
  });

  final String id;
  final String categoryLabel;
  final double confidence;
  final BoundingBox boundingBox;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? heading;
  final String? clientId;

  factory Detection.fromJson(Map<String, dynamic> json) {
    final bbox = json['bounding_box'] as Map<String, dynamic>;
    final location = json['location'] as Map<String, dynamic>?;
    final coords = location?['coordinates'] as List<dynamic>?;
    return Detection(
      id: json['id'] as String,
      categoryLabel: json['category_label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      boundingBox: BoundingBox(
        x: (bbox['x'] as num).toDouble(),
        y: (bbox['y'] as num).toDouble(),
        width: (bbox['width'] as num).toDouble(),
        height: (bbox['height'] as num).toDouble(),
      ),
      latitude: coords != null ? (coords[1] as num).toDouble() : null,
      longitude: coords != null ? (coords[0] as num).toDouble() : null,
      altitude: (json['altitude'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      clientId: json['client_id'] as String?,
    );
  }
}

class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

class AssetCategory {
  const AssetCategory({
    required this.id,
    required this.name,
    required this.detectionLabels,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final List<String> detectionLabels;
  final String? icon;
  final String? color;

  factory AssetCategory.fromJson(Map<String, dynamic> json) {
    return AssetCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      detectionLabels: (json['detection_labels'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      icon: json['icon'] as String?,
      color: json['color'] as String?,
    );
  }
}

class SpatialAnchor {
  const SpatialAnchor({
    required this.id,
    required this.anchorId,
    required this.latitude,
    required this.longitude,
    this.assetId,
    this.altitude,
    this.heading,
    this.cameraOrientation,
    this.assetName,
    this.status,
    this.confidence,
    this.distance,
  });

  final String id;
  final String anchorId;
  final String? assetId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? heading;
  final Map<String, double>? cameraOrientation;
  final String? assetName;
  final String? status;
  final double? confidence;
  final double? distance;
}

class SurveySession {
  const SurveySession({
    required this.id,
    required this.projectId,
    required this.coveragePercentage,
    this.endedAt,
    this.clientId,
  });

  final String id;
  final String projectId;
  final double coveragePercentage;
  final DateTime? endedAt;
  final String? clientId;

  factory SurveySession.fromJson(Map<String, dynamic> json) {
    return SurveySession(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      coveragePercentage: (json['coverage_percentage'] as num).toDouble(),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      clientId: json['client_id'] as String?,
    );
  }
}

class AnalyticsDashboard {
  const AnalyticsDashboard({
    required this.coverage,
    required this.verified,
    required this.pending,
    required this.rejected,
    required this.notSurveyed,
    required this.conflicts,
    required this.total,
  });

  final double coverage;
  final int verified;
  final int pending;
  final int rejected;
  final int notSurveyed;
  final int conflicts;
  final int total;

  factory AnalyticsDashboard.fromJson(Map<String, dynamic> json) {
    final assets = json['assets'] as Map<String, dynamic>;
    return AnalyticsDashboard(
      coverage: (json['coverage'] as num).toDouble(),
      verified: assets['verified'] as int,
      pending: assets['pending'] as int,
      rejected: assets['rejected'] as int,
      notSurveyed: assets['notSurveyed'] as int,
      conflicts: json['conflicts'] as int,
      total: assets['total'] as int,
    );
  }
}
