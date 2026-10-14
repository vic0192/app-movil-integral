import 'package:biomedica_app/widgets/turn_queue_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('avanza el turno de demostración y permite reiniciarlo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: TurnQueueDemo())),
      ),
    );

    expect(find.text('B-024'), findsOneWidget);
    expect(find.text('EN ESPERA'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final advance = find.byKey(const ValueKey('advance-turn-demo'));
    await tester.tap(advance);
    await tester.pumpAndSettle();

    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(advance);
    await tester.pumpAndSettle();
    await tester.tap(advance);
    await tester.pumpAndSettle();

    expect(find.text('EN CONSULTA'), findsOneWidget);
    expect(find.text('Ahora'), findsOneWidget);

    await tester.tap(advance);
    await tester.pumpAndSettle();

    expect(find.text('ATENDIDO'), findsOneWidget);
    expect(find.text('Finalizado'), findsOneWidget);
    expect(find.text('Reiniciar demostración'), findsOneWidget);

    await tester.tap(advance);
    await tester.pumpAndSettle();

    expect(find.text('EN ESPERA'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
  });
}
