import 'core_api_client.dart';
import '../models/app_user_profile.dart';

abstract interface class AccountRepository {
  Future<AppUserProfile> signIn(String email, String password);

  Future<AppUserProfile> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<AppUserProfile?> restoreSession();

  Future<void> signOut();
}

class RelationalAccountRepository implements AccountRepository {
  RelationalAccountRepository({CoreApiClient? api})
    : _api = api ?? CoreApiClient.instance;

  final CoreApiClient _api;

  @override
  Future<AppUserProfile> signIn(String email, String password) async {
    try {
      final response = await _api.post('/api/auth/login', {
        'email': email.trim(),
        'password': password,
      });
      return _saveSession(response);
    } on CoreApiException catch (error) {
      throw AccountRepositoryException(error.message);
    }
  }

  @override
  Future<AppUserProfile> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.post('/api/auth/register', {
        'displayName': displayName.trim(),
        'email': email.trim(),
        'password': password,
      });
      return _saveSession(response);
    } on CoreApiException catch (error) {
      throw AccountRepositoryException(error.message);
    }
  }

  Future<AppUserProfile> _saveSession(Map<String, dynamic> response) async {
    final token = response['token'];
    final user = response['user'];
    if (token is! String || token.isEmpty || user is! Map) {
      throw const AccountRepositoryException(
        'La API no devolvió una sesión de usuario válida.',
      );
    }
    await _api.saveToken(token);
    return _profile(user);
  }

  @override
  Future<AppUserProfile?> restoreSession() async {
    if (await _api.readToken() == null) return null;
    try {
      final response = await _api.get('/api/auth/me');
      final user = response['user'];
      if (user is! Map) {
        throw const AccountRepositoryException(
          'La API no devolvió un perfil de usuario válido.',
        );
      }
      return _profile(user);
    } on CoreApiException catch (error) {
      if (error.statusCode == 401) await _api.clearToken();
      throw AccountRepositoryException(error.message);
    }
  }

  @override
  Future<void> signOut() => _api.clearToken();

  AppUserProfile _profile(Map<dynamic, dynamic> data) {
    try {
      return AppUserProfile.fromMap(
        data['uid'] as String,
        Map<String, dynamic>.from(data),
      );
    } on FormatException catch (error) {
      throw AccountRepositoryException(error.message);
    } on TypeError {
      throw const AccountRepositoryException(
        'La API devolvió campos de perfil inválidos.',
      );
    }
  }
}

class AccountRepositoryException implements Exception {
  const AccountRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
