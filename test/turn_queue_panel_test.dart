import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:biomedica_app/data/clinic_turn_repository.dart';
import 'package:biomedica_app/widgets/turn_queue_panel.dart';

void main() {
  testWidgets('shows real active queue data and the empty patient-turn state', (
    tester,
  ) async {
    final activeTurn = ClinicTurn(
      ticketCode: 'C-105',
      service: 'Consulta general',
      room: 'Sala 4',
      status: 'en_atencion',
      etaMinutes: 0,
      updatedAt: DateTime.utc(2026, 11, 6, 19),
    );
    final waitingTurn = ClinicTurn(
      ticketCode: 'C-106',
      service: 'Cardiología',
      room: 'Sala 2',
      status: 'en_espera',
      etaMinutes: 15,
      updatedAt: DateTime.utc(2026, 11, 6, 19),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TurnQueuePanel(
              patientTurn: null,
              activeQueue: [activeTurn, waitingTurn],
              loading: false,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('No tienes un turno activo asignado.'), findsOneWidget);
    expect(find.text('C-105'), findsOneWidget);
    expect(find.text('C-106'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('B-024'), findsNothing);
  });
}
