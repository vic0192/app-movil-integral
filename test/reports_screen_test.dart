import 'dart:async';

import 'package:biomedica_app/data/supabase_report_repository.dart';
import 'package:biomedica_app/models/app_user_profile.dart';
import 'package:biomedica_app/models/health_report.dart';
import 'package:biomedica_app/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeReportRepository repository;

  setUp(() => repository = _FakeReportRepository());
  tearDown(() async => repository.close());

  testWidgets('TC01 - alta válida asigna ID automáticamente y consulta', (
    tester,
  ) async {
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await _fillForm(
      tester,
      malestar: 'Fiebre',
      description: 'No enciende la pantalla',
      priority: 'Media',
    );

    expect(find.text('AUTO001'), findsOneWidget);
    expect(find.text('Fiebre'), findsWidgets);
    expect(find.text('No enciende la pantalla'), findsOneWidget);
    expect(find.text('Prioridad: Media'), findsOneWidget);
    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.malestar, 'Fiebre');
  });

  testWidgets('TC02 - rechaza descripción vacía', (tester) async {
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('newReport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe la descripción.'), findsOneWidget);
    expect(repository.reports, isEmpty);
  });

  testWidgets('TC09 - exige detalle cuando se selecciona Otro', (
    tester,
  ) async {
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('newReport')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reportMalestar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otro').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reportOtherMalestar')),
      '   ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reportDescription')),
      '   ',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe el otro malestar.'), findsOneWidget);
    expect(find.text('Escribe la descripción.'), findsOneWidget);
    expect(repository.reports, isEmpty);
  });

  testWidgets('TC10 - las opciones sugeridas consideran padecimientos', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      repository,
      chronicConditions: const ['Asma'],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('newReport')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reportMalestar')));
    await tester.pumpAndSettle();
    expect(find.text('Falta de aire'), findsWidgets);
    expect(find.text('Tos'), findsWidgets);
    expect(find.text('Dolor articular'), findsNothing);
  });

  testWidgets('TC11 - captura otro malestar y genera ID sin intervención', (
    tester,
  ) async {
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await _fillForm(
      tester,
      malestar: 'Otro',
      otherMalestar: 'Visión borrosa temporal',
      description: 'Comenzó esta mañana',
    );

    expect(repository.reports.single.id, 'AUTO001');
    expect(repository.reports.single.otherMalestar, 'Visión borrosa temporal');
    expect(find.text('Otro: Visión borrosa temporal'), findsOneWidget);
  });

  testWidgets('TC12 - longitudes máximas del reporte son incluyentes', (
    tester,
  ) async {
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await _fillForm(
      tester,
      malestar: 'Otro',
      otherMalestar: 'E' * 100,
      description: 'D' * 500,
    );

    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.id, 'AUTO001');
    expect(repository.reports.single.otherMalestar, 'E' * 100);
    expect(repository.reports.single.description, 'D' * 500);
  });

  test('TC03 - rechaza guardar dos veces el ID REP001', () async {
    const draft = HealthReportDraft(
      id: 'REP001',
      equipment: 'Fiebre',
      malestar: 'Fiebre',
      description: 'Falla de encendido',
      priority: 'Media',
    );
    await repository.createReport(draft);

    await expectLater(
      repository.createReport(draft),
      throwsA(isA<DuplicateReportIdException>()),
    );
    expect(repository.reports, hasLength(1));
    expect(repository.reports.single.description, 'Falla de encendido');
  });

  testWidgets('TC04 - cambia prioridad de Media a Alta', (tester) async {
    repository.seed(_report(priority: 'Media'));
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Acciones del reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reportPriority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actualizar'));
    await tester.pumpAndSettle();

    expect(find.text('Prioridad: Alta'), findsOneWidget);
    expect(repository.reports.single.priority, 'Alta');
  });

  testWidgets('TC05 - elimina y deja de mostrar el reporte', (tester) async {
    repository.seed(_report());
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Acciones del reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();

    expect(find.text('REP001'), findsNothing);
    expect(repository.reports, isEmpty);
  });

  testWidgets('TC06 - búsqueda REP999 informa resultado vacío', (tester) async {
    repository.seed(_report());
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('searchReport')),
      'REP999',
    );
    await tester.pumpAndSettle();

    expect(find.text('No se encontró el reporte "rep999".'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC07 - pérdida de conexión informa error de escritura', (
    tester,
  ) async {
    repository.createError = const ReportStoreException(
      'Sin conexión con la API. Los cambios no se guardaron.',
    );
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    await _fillForm(
      tester,
      malestar: 'Falta de aire',
      description: 'Alarma activa',
    );

    expect(
      find.text('Sin conexión con la API. Los cambios no se guardaron.'),
      findsOneWidget,
    );
    expect(repository.reports, isEmpty);
  });

  testWidgets('TC08 - los reportes persisten tras recrear la pantalla', (
    tester,
  ) async {
    repository.seed(_report());
    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('REP001'), findsOneWidget);

    await _pumpScreen(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('REP001'), findsOneWidget);
    expect(find.text('Monitor cardiaco'), findsOneWidget);
  });
}

Future<void> _fillForm(
  WidgetTester tester, {
  String malestar = 'Fiebre',
  String? otherMalestar,
  required String description,
  String priority = 'Media',
}) async {
  await tester.tap(find.byKey(const ValueKey('newReport')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('reportMalestar')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(malestar).last);
  await tester.pumpAndSettle();
  if (otherMalestar != null) {
    await tester.enterText(
      find.byKey(const ValueKey('reportOtherMalestar')),
      otherMalestar,
    );
  }
  await tester.enterText(
    find.byKey(const ValueKey('reportDescription')),
    description,
  );
  if (priority != 'Media') {
    await tester.tap(find.byKey(const ValueKey('reportPriority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(priority).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Guardar'));
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ReportRepository repository,
  {List<String> chronicConditions = const []}
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReportsScreen(
          patientName: 'Paciente de prueba',
          chronicConditions: chronicConditions,
          repository: repository,
        ),
      ),
    ),
  );
}

HealthReport _report({String priority = 'Media'}) => HealthReport(
  id: 'REP001',
  equipment: 'Monitor cardiaco',
  description: 'No enciende la pantalla',
  priority: priority,
  createdAt: DateTime(2026, 10, 16),
  updatedAt: DateTime(2026, 10, 16),
);

class _FakeReportRepository implements ReportRepository {
  final _controller = StreamController<List<HealthReport>>.broadcast();
  final List<HealthReport> reports = [];
  ReportStoreException? queryError;
  ReportStoreException? createError;

  @override
  String? get ownerUid => 'test-owner';

  @override
  AppRole? get role => AppRole.patient;

  @override
  Future<void> initialize() async {}

  @override
  Stream<List<HealthReport>> watchReports() async* {
    if (queryError case final error?) throw error;
    yield List.unmodifiable(reports);
    yield* _controller.stream;
  }

  @override
  Future<String> createReport(
    HealthReportDraft draft, {
    String? documentId,
  }) async {
    final error = createError;
    if (error != null) throw error;
    final id = documentId ?? draft.id;
    if (reports.any((report) => report.id == id)) {
      throw DuplicateReportIdException(id);
    }
    final now = DateTime.now();
    reports.insert(
      0,
      HealthReport(
        id: id.isEmpty ? 'AUTO001' : id,
        equipment: draft.malestar ?? draft.equipment,
        description: draft.description,
        priority: draft.priority,
        createdAt: now,
        updatedAt: now,
        malestar: draft.malestar ?? draft.equipment,
        otherMalestar: draft.otherMalestar,
        onsetAt: draft.onsetAt,
      ),
    );
    _emit();
    return reports.first.id;
  }

  @override
  Future<void> updateReport(String id, HealthReportDraft draft) async {
    final index = reports.indexWhere((report) => report.id == id);
    if (index < 0) throw ReportNotFoundException(id);
    final original = reports[index];
    reports[index] = HealthReport(
      id: id,
      equipment: draft.malestar ?? draft.equipment,
      description: draft.description,
      priority: draft.priority,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      malestar: draft.malestar ?? draft.equipment,
      otherMalestar: draft.otherMalestar,
      onsetAt: draft.onsetAt,
    );
    _emit();
  }

  @override
  Future<void> deleteReport(String id) async {
    final index = reports.indexWhere((report) => report.id == id);
    if (index < 0) throw ReportNotFoundException(id);
    reports.removeAt(index);
    _emit();
  }

  void seed(HealthReport report) {
    reports.add(report);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(reports));
  }

  Future<void> close() => _controller.close();
}
