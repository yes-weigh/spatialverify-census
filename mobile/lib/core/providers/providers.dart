import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../../core/database/database.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/sync/sync_engine.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/mission/data/firebase_mission_repository.dart';
import '../../features/mission/data/local_registry_service.dart';
import '../../features/scanner/data/detection_service.dart';
import '../../features/ar/data/ar_anchor_service.dart';
import '../../features/identity/data/spatial_identity_service.dart';

final secureStorageProvider = Provider<SecureLocalStorage>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

final localRegistryProvider = Provider<LocalRegistryService>((ref) => LocalRegistryService());

final firebaseMissionRepositoryProvider = Provider<FirebaseMissionRepository>((ref) {
  return FirebaseMissionRepository();
});

final firebaseAuthRepositoryProvider = Provider<FirebaseAuthRepository>((ref) {
  return FirebaseAuthRepository(
    database: ref.watch(databaseProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

final restAuthRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  if (AppConfig.useFirebase) {
    return ref.watch(firebaseAuthRepositoryProvider);
  }
  return ref.watch(restAuthRepositoryProvider);
});

final authRepositoryProvider = Provider<AuthService>((ref) => ref.watch(authServiceProvider));

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
  );
});

final detectionServiceProvider = Provider<DetectionService>((ref) {
  final service = DetectionService(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final arAnchorServiceProvider = Provider<ArAnchorService>((ref) {
  return ArAnchorService(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
});

final spatialIdentityServiceProvider = Provider<SpatialIdentityService>((ref) {
  final service = SpatialIdentityService(
    apiClient: ref.watch(apiClientProvider),
    database: ref.watch(databaseProvider),
    syncEngine: ref.watch(syncEngineProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider), ref);
});

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  final User? user;
  final bool isLoading;
  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading, String? error}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repository, this._ref) : super(const AuthState()) {
    _checkAuth();
  }

  final AuthService _repository;
  final Ref _ref;

  Future<void> _checkAuth() async {
    state = state.copyWith(isLoading: true);
    if (AppConfig.standaloneMode) {
      state = AuthState(
        user: User(
          id: 'local-enumerator',
          email: 'field@local',
          firstName: 'Field',
          lastName: 'Enumerator',
          role: UserRole.fieldWorker,
        ),
        isLoading: false,
      );
      return;
    }
    try {
      final user = await _repository.getCurrentUser();
      if (user != null && AppConfig.useFirebase) {
        await _ref.read(firebaseMissionRepositoryProvider).ensureWorkspace();
      }
      state = AuthState(user: user, isLoading: false);
    } catch (e) {
      state = AuthState(isLoading: false, error: e.toString());
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final (user, _) = await _repository.login(email, password);
      if (AppConfig.useFirebase) {
        await _ref.read(firebaseMissionRepositoryProvider).ensureWorkspace();
      }
      state = AuthState(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = AuthState(isLoading: false, error: 'Invalid credentials');
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final (user, _) = await _repository.register(email: email, password: password);
      if (AppConfig.useFirebase) {
        await _ref.read(firebaseMissionRepositoryProvider).ensureWorkspace();
      }
      state = AuthState(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = AuthState(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState();
  }
}

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  if (AppConfig.standaloneMode) {
    final registry = ref.watch(localRegistryProvider);
    await registry.init();
    return registry.listProjects();
  }
  if (AppConfig.useFirebase) {
    final cloud = ref.watch(firebaseMissionRepositoryProvider);
    await cloud.ensureWorkspace();
    return cloud.listProjects();
  }
  final repo = ref.watch(projectRepositoryProvider);
  return repo.getProjects();
});

final selectedProjectProvider = StateProvider<Project?>((ref) => null);

final assetsProvider = FutureProvider.family<List<Asset>, String>((ref, projectId) async {
  final db = ref.watch(databaseProvider);
  final localAssets = await db.getAssetsByProject(projectId);
  return localAssets
      .map((a) => Asset(
            id: a.id,
            projectId: a.projectId,
            categoryId: a.categoryId,
            name: a.name,
            status: _parseAssetStatus(a.status),
            latitude: a.latitude,
            longitude: a.longitude,
            altitude: a.altitude,
            heading: a.heading,
            clientId: a.clientId,
            version: a.version,
          ))
      .toList();
});

AssetStatus _parseAssetStatus(String status) {
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

final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref.watch(syncEngineProvider));
});

class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.lastResult,
    this.lastSyncAt,
  });

  final bool isSyncing;
  final SyncResult? lastResult;
  final DateTime? lastSyncAt;
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._engine) : super(const SyncState());

  final SyncEngine _engine;

  Future<void> sync(String projectId) async {
    state = SyncState(isSyncing: true, lastSyncAt: state.lastSyncAt);
    final result = await _engine.sync(projectId);
    state = SyncState(
      isSyncing: false,
      lastResult: result,
      lastSyncAt: DateTime.now(),
    );
  }
}
