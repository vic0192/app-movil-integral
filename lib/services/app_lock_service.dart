import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AppLockStore {
  Future<String?> readPassword();
  Future<void> writePassword(String password);
  Future<void> deletePassword();
}

class SecureAppLockStore implements AppLockStore {
  SecureAppLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _passwordKey = 'biomedica_app_lock_password';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  @override
  Future<void> writePassword(String password) =>
      _storage.write(key: _passwordKey, value: password);

  @override
  Future<void> deletePassword() => _storage.delete(key: _passwordKey);
}

class AppLockService {
  AppLockService({AppLockStore? store})
    : _store = store ?? SecureAppLockStore();

  static const minimumPasswordLength = 8;
  final AppLockStore _store;

  Future<bool> isEnabled() async => await _store.readPassword() != null;

  Future<bool> verify(String password) async {
    final savedPassword = await _store.readPassword();
    return savedPassword != null && savedPassword == password;
  }

  Future<void> setPassword(String password) async {
    if (password.trim().length < minimumPasswordLength ||
        password.length > 128) {
      throw ArgumentError('La contraseña debe tener entre 8 y 128 caracteres.');
    }
    await _store.writePassword(password);
  }

  Future<void> removePassword() => _store.deletePassword();
}
