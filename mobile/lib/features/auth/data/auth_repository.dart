import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../../../core/network/api_client.dart';
import '../../../core/database/database.dart';
import '../../../core/models/models.dart';
import '../../../core/storage/secure_storage.dart';

import 'auth_service.dart';

class AuthRepository implements AuthService {
  AuthRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SecureLocalStorage storage,
  })  : _api = apiClient,
        _db = database,
        _storage = storage;

  final ApiClient _api;
  final AppDatabase _db;
  final SecureLocalStorage _storage;
  final _uuid = const Uuid();

  @override
  Future<(User, AuthTokens)> login(String email, String password) async {
    var deviceId = _storage.deviceId;
    deviceId ??= _uuid.v4();
    await _storage.setDeviceId(deviceId);

    final response = await _api.post('/auth/login', data: {
      'email': email,
      'password': password,
      'deviceId': deviceId,
    });

    final data = response.data as Map<String, dynamic>;
    final tokens = AuthTokens.fromJson(data);
    final user = User.fromJson(data['user'] as Map<String, dynamic>);

    await _api.saveTokens(tokens.accessToken, tokens.refreshToken);
    await _cacheUser(user);

    return (user, tokens);
  }

  @override
  Future<(User, AuthTokens)> register({
    required String email,
    required String password,
    String firstName = 'Field',
    String lastName = 'Enumerator',
  }) async {
    throw UnsupportedError('Registration is only available with Firebase cloud mode');
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _api.dio.options.headers['Authorization'];
    try {
      await _api.post('/auth/logout', data: {
        'refreshToken': refreshToken,
      });
    } catch (_) {}
    await _api.clearTokens();
  }

  @override
  Future<User?> getCurrentUser() async {
    final hasTokens = await _api.hasTokens();
    if (!hasTokens) return null;

    try {
      final response = await _api.get('/auth/me');
      final user = User.fromJson(response.data as Map<String, dynamic>);
      await _cacheUser(user);
      return user;
    } catch (_) {
      final cached = await (_db.select(_db.localUsers)..limit(1)).getSingleOrNull();
      if (cached != null) {
        return User(
          id: cached.id,
          email: cached.email,
          firstName: cached.firstName,
          lastName: cached.lastName,
          role: _parseUserRole(cached.role),
        );
      }
      return null;
    }
  }

  Future<void> _cacheUser(User user) async {
    await _db.into(_db.localUsers).insertOnConflictUpdate(
          LocalUsersCompanion.insert(
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role.name,
            cachedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<bool> requestPasswordReset(String email) async {
    await _api.post('/auth/password-reset/request', data: {'email': email});
    return true;
  }

  Future<bool> resetPassword(String token, String password) async {
    await _api.post('/auth/password-reset/confirm', data: {
      'token': token,
      'password': password,
    });
    return true;
  }
}

UserRole _parseUserRole(String role) {
  switch (role) {
    case 'admin':
      return UserRole.admin;
    case 'supervisor':
      return UserRole.supervisor;
    default:
      return UserRole.fieldWorker;
  }
}

class ProjectRepository {
  ProjectRepository({
    required ApiClient apiClient,
    required AppDatabase database,
  })  : _api = apiClient,
        _db = database;

  final ApiClient _api;
  final AppDatabase _db;

  Future<List<Project>> getProjects() async {
    try {
      final response = await _api.get('/projects');
      final list = (response.data as List<dynamic>)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
      await _cacheProjects(list);
      return list;
    } catch (_) {
      final cached = await _db.select(_db.localProjects).get();
      return cached
          .map((p) => Project(
                id: p.id,
                name: p.name,
                description: p.description,
                boundary: p.boundaryJson != null
                    ? jsonDecode(p.boundaryJson!) as Map<String, dynamic>
                    : null,
                surveyRules: jsonDecode(p.surveyRulesJson) as Map<String, dynamic>,
                isActive: p.isActive,
              ))
          .toList();
    }
  }

  Future<Project?> getProject(String id) async {
    try {
      final response = await _api.get('/projects/$id');
      return Project.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      final cached = await (_db.select(_db.localProjects)
            ..where((p) => p.id.equals(id)))
          .getSingleOrNull();
      if (cached == null) return null;
      return Project(
        id: cached.id,
        name: cached.name,
        description: cached.description,
        boundary: cached.boundaryJson != null
            ? jsonDecode(cached.boundaryJson!) as Map<String, dynamic>
            : null,
        surveyRules: jsonDecode(cached.surveyRulesJson) as Map<String, dynamic>,
      );
    }
  }

  Future<List<AssetCategory>> getCategories(String projectId) async {
    try {
      final response = await _api.get('/projects/$projectId/categories');
      final list = (response.data as List<dynamic>)
          .map((e) => AssetCategory.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final cat in list) {
        await _db.into(_db.localAssetCategories).insertOnConflictUpdate(
              LocalAssetCategoriesCompanion.insert(
                id: cat.id,
                projectId: projectId,
                name: cat.name,
                detectionLabelsJson: jsonEncode(cat.detectionLabels),
                icon: Value(cat.icon),
                color: Value(cat.color),
              ),
            );
      }
      return list;
    } catch (_) {
      final cached = await (_db.select(_db.localAssetCategories)
            ..where((c) => c.projectId.equals(projectId)))
          .get();
      return cached
          .map((c) => AssetCategory(
                id: c.id,
                name: c.name,
                detectionLabels: (jsonDecode(c.detectionLabelsJson) as List<dynamic>)
                    .map((e) => e as String)
                    .toList(),
                icon: c.icon,
                color: c.color,
              ))
          .toList();
    }
  }

  Future<void> _cacheProjects(List<Project> projects) async {
    for (final p in projects) {
      await _db.into(_db.localProjects).insertOnConflictUpdate(
            LocalProjectsCompanion.insert(
              id: p.id,
              name: p.name,
              description: Value(p.description),
              boundaryJson: Value(
                p.boundary != null ? jsonEncode(p.boundary) : null,
              ),
              surveyRulesJson: jsonEncode(p.surveyRules),
              isActive: Value(p.isActive),
              syncedAt: Value(DateTime.now()),
            ),
          );
    }
  }
}
