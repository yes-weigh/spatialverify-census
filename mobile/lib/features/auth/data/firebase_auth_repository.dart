import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/models/models.dart';
import '../../../core/storage/secure_storage.dart';
import 'auth_service.dart';

class FirebaseAuthRepository implements AuthService {
  FirebaseAuthRepository({
    fb.FirebaseAuth? auth,
    required AppDatabase database,
    required SecureLocalStorage storage,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _db = database,
        _storage = storage;

  final fb.FirebaseAuth _auth;
  final AppDatabase _db;
  final SecureLocalStorage _storage;
  final _uuid = const Uuid();

  @override
  Future<(User, AuthTokens)> login(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    final user = await _mapAndCache(cred.user!);
    final token = await cred.user!.getIdToken() ?? '';
    return (user, AuthTokens(accessToken: token, refreshToken: '', expiresIn: 3600));
  }

  @override
  Future<(User, AuthTokens)> register({
    required String email,
    required String password,
    String firstName = 'Field',
    String lastName = 'Enumerator',
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user?.updateDisplayName('$firstName $lastName');
    final user = await _mapAndCache(cred.user!);
    final token = await cred.user!.getIdToken() ?? '';
    return (user, AuthTokens(accessToken: token, refreshToken: '', expiresIn: 3600));
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
  }

  @override
  Future<User?> getCurrentUser() async {
    final fbUser = _auth.currentUser;
    if (fbUser == null) {
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
    return _mapAndCache(fbUser);
  }

  @override
  Future<bool> requestPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
    return true;
  }

  Future<User> _mapAndCache(fb.User fbUser) async {
    final display = fbUser.displayName?.trim();
    String firstName = 'Field';
    String lastName = 'Enumerator';
    if (display != null && display.isNotEmpty) {
      final parts = display.split(RegExp(r'\s+'));
      firstName = parts.first;
      if (parts.length > 1) lastName = parts.sublist(1).join(' ');
    }

    var deviceId = _storage.deviceId;
    deviceId ??= _uuid.v4();
    await _storage.setDeviceId(deviceId);

    final user = User(
      id: fbUser.uid,
      email: fbUser.email ?? '',
      firstName: firstName,
      lastName: lastName,
      role: UserRole.fieldWorker,
    );
    await _cacheUser(user);
    return user;
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
