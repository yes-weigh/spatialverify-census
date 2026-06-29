import '../../../core/models/models.dart';

/// Shared auth contract — REST JWT or Firebase email/password.
abstract class AuthService {
  Future<(User, AuthTokens)> login(String email, String password);

  Future<(User, AuthTokens)> register({
    required String email,
    required String password,
    String firstName = 'Field',
    String lastName = 'Enumerator',
  });

  Future<void> logout();

  Future<User?> getCurrentUser();

  Future<bool> requestPasswordReset(String email);
}
