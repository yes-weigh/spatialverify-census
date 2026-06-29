import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import '../../core/database/database.dart';
import '../../core/storage/secure_storage.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/mission/data/firebase_mission_repository.dart';
import '../updates/app_update_service.dart';

final secureStorageProvider = Provider<SecureLocalStorage>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final firebaseMissionRepositoryProvider = Provider<FirebaseMissionRepository>((ref) {
  return FirebaseMissionRepository();
});

final firebaseAuthRepositoryProvider = Provider<FirebaseAuthRepository>((ref) {
  return FirebaseAuthRepository(
    database: ref.watch(databaseProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  return ref.watch(firebaseAuthRepositoryProvider);
});

final authRepositoryProvider = Provider<AuthService>((ref) => ref.watch(authServiceProvider));

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) => AppUpdateService());

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
    try {
      final user = await _repository.getCurrentUser();
      if (user != null) {
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
      await _ref.read(firebaseMissionRepositoryProvider).ensureWorkspace();
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
      await _ref.read(firebaseMissionRepositoryProvider).ensureWorkspace();
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
  final cloud = ref.watch(firebaseMissionRepositoryProvider);
  await cloud.ensureWorkspace();
  return cloud.listProjects();
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
