// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biomedica_app/bio_medica_app.dart';
import 'package:biomedica_app/data/account_repository.dart';
import 'package:biomedica_app/models/app_user_profile.dart';

void main() {
  testWidgets('muestra el acceso de pacientes BioMedica', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.text('BioMedica'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Explorar demostración'), findsNothing);
    expect(tester.widget<TextField>(_passwordField()).obscureText, isTrue);
  });

  testWidgets('permite mostrar y volver a ocultar la contraseña', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final password = _passwordField();

    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isFalse);

    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
  });

  testWidgets('rechaza correo vacío o formado solo por espacios', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byKey(const ValueKey('accountEmail')), '   ');
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'BioMedica2026',
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu correo.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza un correo que excede la longitud máxima', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    tester
            .widget<TextFormField>(find.byKey(const ValueKey('accountEmail')))
            .controller!
            .text =
        'u' * 255;
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'BioMedica2026',
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(
      find.text('El correo excede la longitud permitida.'),
      findsOneWidget,
    );
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza contraseñas menores de ocho caracteres', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(
      find.byKey(const ValueKey('accountEmail')),
      'paciente@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'corta',
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza contraseñas que exceden la longitud máxima', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.enterText(
      find.byKey(const ValueKey('accountEmail')),
      'paciente@example.com',
    );
    tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('accountPassword')),
            )
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

  testWidgets('rechaza nombres de registro vacíos, cortos o demasiado largos', (
    tester,
  ) async {
    await _openRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('registrationFirstName')),
      '  ',
    );
    await _submitRegistration(tester);

    expect(find.text('Escribe tu nombre.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);

    tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('registrationFirstName')),
            )
            .controller!
            .text =
        'a' * 101;
    await _submitRegistration(tester);

    expect(
      find.text('El nombre excede la longitud permitida.'),
      findsOneWidget,
    );
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza nombres de registro menores de tres caracteres', (
    tester,
  ) async {
    await _openRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('registrationFirstName')),
      'A',
    );
    await _submitRegistration(tester);

    expect(find.text('Escribe tu nombre.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('rechaza correos de registro con formato inválido', (
    tester,
  ) async {
    await _openRegistration(tester);

    for (final email in [
      'nombre@',
      '@dominio.com',
      'nombre@dominio',
      'nombre con espacio@dominio.com',
      'nombre@-dominio.com',
      'nombre@dominio..com',
      'nombre..apellido@dominio.com',
      '${'a' * 65}@example.com',
      'a@${'b' * 64}.com',
    ]) {
      await tester.enterText(find.byKey(const ValueKey('accountEmail')), email);
      await _submitRegistration(tester);

      expect(
        find.text('Ingresa un correo válido.'),
        findsOneWidget,
        reason: 'Debe rechazar $email',
      );
      expect(find.text('Mis signos vitales'), findsNothing);
    }
  });

  testWidgets('acepta un correo y contraseña de registro válidos', (
    tester,
  ) async {
    await _openRegistration(tester);
    await _submitRegistration(tester);

    expect(find.text('Mis signos vitales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rechaza una confirmación de contraseña diferente', (
    tester,
  ) async {
    await _openRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('confirmPassword')),
      'OtraClave123',
    );
    await _submitRegistration(tester);

    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(find.text('Mis signos vitales'), findsNothing);
  });

  testWidgets('permite dejar vacío el padecimiento opcional "Otra"', (
    tester,
  ) async {
    await _openRegistration(tester);
    await tester.ensureVisible(find.text('Otra'));
    await tester.tap(find.text('Otra'));
    await tester.pumpAndSettle();
    await _submitRegistration(tester);

    expect(find.text('Mis signos vitales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acepta la longitud máxima de 30 para contraseña', (
    tester,
  ) async {
    await _openRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'P' * 30,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('confirmPassword')));
    await tester.enterText(
      find.byKey(const ValueKey('confirmPassword')),
      'P' * 30,
    );
    await _submitRegistration(tester);

    expect(find.text('Mis signos vitales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra un error genérico ante credenciales incorrectas', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.enterText(
      find.byKey(const ValueKey('accountEmail')),
      'paciente@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'Incorrecta123',
    );
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

  testWidgets('permite el acceso con credenciales válidas', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(
      find.byKey(const ValueKey('accountEmail')),
      'paciente@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('accountPassword')),
      'BioMedica2026',
    );
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Mis signos vitales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 640), Size(375, 812), Size(414, 896)]) {
    testWidgets('adapta el acceso a ${size.width} × ${size.height}', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_app());
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Explorar demostración'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openRegistration(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.ensureVisible(find.text('Crear una cuenta'));
  await tester.tap(find.text('Crear una cuenta'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('registrationFirstName')),
    'Ana',
  );
  await tester.enterText(
    find.byKey(const ValueKey('registrationLastName')),
    'Prueba',
  );
  final dateOfBirth = find.byKey(const ValueKey('registrationDateOfBirth'));
  await tester.ensureVisible(dateOfBirth);
  await tester.tap(dateOfBirth);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aceptar'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('accountEmail')));
  await tester.enterText(
    find.byKey(const ValueKey('accountEmail')),
    'ana@example.com',
  );
  await tester.enterText(
    find.byKey(const ValueKey('accountPassword')),
    'Clave1234',
  );
  await tester.ensureVisible(find.byKey(const ValueKey('confirmPassword')));
  await tester.enterText(
    find.byKey(const ValueKey('confirmPassword')),
    'Clave1234',
  );
}

Future<void> _submitRegistration(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Crear cuenta'));
  await tester.tap(find.text('Crear cuenta'));
  await tester.pumpAndSettle();
}

Widget _app() => BioMedicaApp(accountRepository: _FakeAccountRepository());

Finder _passwordField() => find.descendant(
  of: find.byKey(const ValueKey('accountPassword')),
  matching: find.byType(TextField),
);

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<AppUserProfile?> restoreSession() async => null;

  @override
  Future<AppUserProfile> signIn(String email, String password) async {
    if (password == 'Incorrecta123') {
      throw const AccountRepositoryException(
        'No se pudo iniciar sesión. Verifica tus datos e inténtalo de nuevo.',
      );
    }
    return AppUserProfile(
      uid: 'demo',
      displayName: 'Paciente de prueba',
      email: email,
      role: AppRole.patient,
    );
  }

  @override
  Future<AppUserProfile?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    required List<String> chronicConditions,
    String? otherChronicCondition,
  }) async => AppUserProfile(
    uid: 'demo',
    displayName: '$firstName $lastName',
    email: email,
    role: AppRole.patient,
  );

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<void> signOut() async {}
}
