import 'package:biomedica_app/data/clinical_video_call_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an invitation without adding patient details to its room', () {
    final call = ClinicalVideoCall.fromMap({
      'id': 'call-1',
      'staff_uid': 'staff-1',
      'patient_uid': 'patient-1',
      'room_name': 'BioMedicaDemo-abcdefghijklmnopqrstuvwx',
      'status': 'ringing',
      'expires_at': '2026-11-27T18:45:00.000Z',
      'created_at': '2026-11-27T18:35:00.000Z',
    });

    expect(call.patientUid, 'patient-1');
    expect(call.inviteUrl, 'https://meet.jit.si/BioMedicaDemo-abcdefghijklmnopqrstuvwx');
    expect(call.inviteUrl, isNot(contains('patient-1')));
  });

  test('rejects room names that do not match the generated format', () {
    expect(
      () => ClinicalVideoCall.fromMap({
        'id': 'call-1',
        'staff_uid': 'staff-1',
        'patient_uid': 'patient-1',
        'room_name': 'patient-1',
        'status': 'ringing',
        'expires_at': '2026-11-27T18:45:00.000Z',
        'created_at': '2026-11-27T18:35:00.000Z',
      }),
      throwsA(isA<ClinicalVideoCallException>()),
    );
  });
}
