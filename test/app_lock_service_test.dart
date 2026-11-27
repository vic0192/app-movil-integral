import 'package:biomedica_app/services/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryAppLockStore implements AppLockStore {
  String? password;

  @override
  Future<void> deletePassword() async {
    password = null;
  }

  @override
  Future<String?> readPassword() async => password;

  @override
  Future<void> writePassword(String password) async {
    this.password = password;
  }
}

void main() {
  test('stores and verifies an app password', () async {
    final service = AppLockService(store: _MemoryAppLockStore());

    await service.setPassword('clave-segura');

    expect(await service.isEnabled(), isTrue);
    expect(await service.verify('clave-segura'), isTrue);
    expect(await service.verify('incorrecta'), isFalse);
  });

  test('rejects short passwords and leaves the lock disabled', () async {
    final service = AppLockService(store: _MemoryAppLockStore());

    await expectLater(service.setPassword('1234567'), throwsArgumentError);
    expect(await service.isEnabled(), isFalse);
  });

  test('removes the stored password when protection is disabled', () async {
    final service = AppLockService(store: _MemoryAppLockStore());
    await service.setPassword('clave-segura');

    await service.removePassword();

    expect(await service.isEnabled(), isFalse);
    expect(await service.verify('clave-segura'), isFalse);
  });
}
