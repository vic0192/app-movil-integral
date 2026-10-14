// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biomedica_app/bio_medica_app.dart';

void main() {
  testWidgets('muestra el acceso de pacientes BioMedica', (tester) async {
    await tester.pumpWidget(const BioMedicaApp());

    expect(find.text('BioMedica'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Explorar demostración'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
      isTrue,
    );
  });

  testWidgets('rechaza usuario vacío o formado solo por espacios', (
    tester,
  ) async {
    await tester.pumpWidget(const BioMedicaApp());
    await tester.enterText(find.byType(TextFormField).at(0), '   ');
    await tester.enterText(find.byType(TextFormField).at(1), 'BioMedica2026');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu usuario.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza un usuario que excede la longitud máxima', (
    tester,
  ) async {
    await tester.pumpWidget(const BioMedicaApp());
    tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text =
        'u' * 31;
    await tester.enterText(find.byType(TextFormField).at(1), 'BioMedica2026');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text('El usuario excede la longitud permitida.'),
      findsOneWidget,
    );
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza contraseñas menores de ocho caracteres', (tester) async {
    await tester.pumpWidget(const BioMedicaApp());
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente');
    await tester.enterText(find.byType(TextFormField).at(1), 'corta');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza contraseñas que exceden la longitud máxima', (
    tester,
  ) async {
    await tester.pumpWidget(const BioMedicaApp());
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente');
    tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text =
        'p' * 31;
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text('La contraseña excede la longitud permitida.'),
      findsOneWidget,
    );
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('muestra un error genérico ante credenciales incorrectas', (
    tester,
  ) async {
    await tester.pumpWidget(const BioMedicaApp());
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente');
    await tester.enterText(find.byType(TextFormField).at(1), 'Incorrecta123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudo iniciar sesión. Verifica tus datos e inténtalo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('permite el acceso simulado con credenciales de prueba', (
    tester,
  ) async {
    await tester.pumpWidget(const BioMedicaApp());
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente');
    await tester.enterText(find.byType(TextFormField).at(1), 'BioMedica2026');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Mis signos vitales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 640), Size(375, 812), Size(414, 896)]) {
    testWidgets('adapta Inicio a ${size.width} × ${size.height}', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const BioMedicaApp());
      await tester.ensureVisible(find.text('Explorar demostración'));
      await tester.tap(find.text('Explorar demostración'));
      await tester.pumpAndSettle();

      expect(find.text('Mis signos vitales'), findsOneWidget);
      expect(find.text('Frecuencia cardiaca'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final linkButton = find.text('Vincular').last;
      await tester.ensureVisible(linkButton);
      await tester.tap(linkButton);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Conectar wearable'), findsOneWidget);
      final sampleButton = find.text('Usar datos de muestra');
      await tester.ensureVisible(sampleButton);
      await tester.tap(sampleButton);
      await tester.pumpAndSettle();

      expect(find.text('BioWatch de demostración'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('75'), findsOneWidget);

      final stopDemo = find.byTooltip('Detener datos de demostración');
      await tester.ensureVisible(stopDemo);
      await tester.tap(stopDemo);
      await tester.pumpAndSettle();

      expect(find.text('Sin wearable vinculado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
