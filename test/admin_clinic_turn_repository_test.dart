import 'package:biomedica_app/data/admin_clinic_turn_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses turns for administration with patient and status', () {
    final turn = AdminClinicTurn.fromMap({
      'id': 'turn-1',
      'ticket_code': 'T-000042',
      'patient_uid': 'patient-1',
      'service': 'Consulta general',
      'room': 'Sala 4',
      'priority': 'media',
      'status': 'en_espera',
      'eta_minutes': 12,
      'created_at': '2026-11-06T18:45:00.000Z',
    });

    expect(turn.id, 'turn-1');
    expect(turn.ticketCode, 'T-000042');
    expect(turn.patientUid, 'patient-1');
    expect(turn.status, 'en_espera');
  });

  test('turn code collisions produce a safe retry message', () {
    final error = AdminClinicTurnException.fromDatabaseCode('23505');

    expect(error.message, contains('código de turno'));
    expect(error.message, contains('inténtalo de nuevo'));
    expect(error.message, isNot(contains('clinic_turns_ticket_code_key')));
  });
}
