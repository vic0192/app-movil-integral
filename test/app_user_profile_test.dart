import 'package:biomedica_app/models/app_user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses each supported role and assigned patient IDs', () {
    for (final role in AppRole.values) {
      final profile = AppUserProfile.fromMap('user-1', {
        'displayName': 'Prueba',
        'email': 'test@example.com',
        'role': role.name,
        'assignedPatientUids': ['patient-1'],
      });

      expect(profile.role, role);
      expect(profile.uid, 'user-1');
      expect(profile.assignedPatientUids, ['patient-1']);
    }
  });

  test('rejects unknown roles rather than falling back to patient', () {
    expect(
      () => AppUserProfile.fromMap('user-1', {
        'displayName': 'Prueba',
        'email': 'test@example.com',
        'role': 'superuser',
      }),
      throwsFormatException,
    );
  });
}
