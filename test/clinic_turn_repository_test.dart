import 'package:flutter_test/flutter_test.dart';
import 'package:biomedica_app/data/clinic_turn_repository.dart';

void main() {
  group('ClinicTurn.fromMap', () {
    test('parses an active turn returned by Supabase', () {
      final turn = ClinicTurn.fromMap({
        'ticket_code': 'C-105',
        'service': 'Consulta general',
        'room': 'Sala 4',
        'status': 'en_espera',
        'eta_minutes': 12,
        'updated_at': '2026-11-06T19:00:00.000Z',
        'created_at': '2026-11-06T18:45:00.000Z',
      });

      expect(turn.ticketCode, 'C-105');
      expect(turn.status, 'en_espera');
      expect(turn.etaMinutes, 12);
      expect(turn.createdAt, DateTime.parse('2026-11-06T18:45:00.000Z'));
    });

    test('rejects terminal statuses and invalid fields', () {
      expect(
        () => ClinicTurn.fromMap({
          'ticket_code': 'C-105',
          'service': 'Consulta general',
          'room': 'Sala 4',
          'status': 'finalizado',
          'eta_minutes': 0,
          'updated_at': '2026-11-06T19:00:00.000Z',
        }),
        throwsA(isA<ClinicTurnException>()),
      );
    });
  });
}
