import 'package:biomedica_app/data/api_report_repository.dart';
import 'package:biomedica_app/models/health_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthReportValidation', () {
    test('allows an omitted ID and accepts the maximum ID length', () {
      expect(HealthReportValidation.id(''), isNull);
      expect(HealthReportValidation.id('R' * 100), isNull);
      expect(HealthReportValidation.id('😀' * 100), isNull);
    });

    test('rejects IDs containing a slash or exceeding 100 characters', () {
      expect(HealthReportValidation.id('REP/001'), contains('/'));
      expect(HealthReportValidation.id('R' * 101), contains('100'));
    });

    test('generates unique UUIDs for report operations', () {
      final first = HealthReportDraft.generateId();
      final second = HealthReportDraft.generateId();

      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(second, isNot(first));
    });

    test('serializes local onset times with an explicit UTC offset', () {
      final localOnset = DateTime(2026, 11, 5, 12, 25);
      const draft = HealthReportDraft(
        id: 'report-id',
        equipment: 'Fiebre',
        description: 'Prueba de fecha',
        priority: 'Media',
      );
      final payload = HealthReportDraft(
        id: draft.id,
        equipment: draft.equipment,
        description: draft.description,
        priority: draft.priority,
        onsetAt: localOnset,
      ).toApiJson();
      final serialized = payload['onsetAt']! as String;

      expect(serialized, endsWith('Z'));
      expect(DateTime.parse(serialized).toLocal(), localOnset);
    });

    test('rejects blank report fields and accepts their maximum lengths', () {
      expect(HealthReportValidation.equipment(' \t '), isNotNull);
      expect(HealthReportValidation.description('  '), isNotNull);
      expect(HealthReportValidation.equipment('E' * 100), isNull);
      expect(HealthReportValidation.equipment('😀' * 100), isNull);
      expect(HealthReportValidation.description('D' * 500), isNull);
    });

    test('rejects report fields exceeding their maximum lengths', () {
      expect(HealthReportValidation.equipment('E' * 101), contains('100'));
      expect(HealthReportValidation.description('D' * 501), contains('500'));
    });

    test('accepts only the supported priority values', () {
      for (final priority in HealthReportValidation.priorities) {
        expect(HealthReportValidation.priority(priority), isNull);
      }
      expect(HealthReportValidation.priority('Urgente'), isNotNull);
      expect(HealthReportValidation.priority(''), isNotNull);
    });

    test('requires a detail when Otro malestar is selected', () {
      expect(HealthReportValidation.malestar('Fiebre'), isNull);
      expect(HealthReportValidation.otherMalestar('', 'Fiebre'), isNull);
      expect(
        HealthReportValidation.otherMalestar('  ', 'Otro'),
        contains('otro malestar'),
      );
      expect(
        HealthReportValidation.otherMalestar('Visión borrosa', 'Otro'),
        isNull,
      );
    });

    test('rejects a symptom onset time in the future', () {
      final now = DateTime(2026, 10, 27, 12);
      expect(
        HealthReportValidation.onsetAt(
          now.add(const Duration(minutes: 1)),
          now: now,
        ),
        contains('futuro'),
      );
      expect(HealthReportValidation.onsetAt(now, now: now), isNull);
    });
  });

  group('ApiReportRepository input guards', () {
    const invalidEquipment = HealthReportDraft(
      id: '',
      equipment: ' \t ',
      description: 'Falla de encendido',
      priority: 'Media',
    );
    const validReport = HealthReportDraft(
      id: '',
      equipment: 'Monitor cardiaco',
      description: 'Falla de encendido',
      priority: 'Media',
    );

    test('rejects an invalid draft before requiring a session', () {
      expect(
        () => ApiReportRepository().createReport(invalidEquipment),
        throwsA(isA<ReportStoreException>()),
      );
    });

    test('rejects an invalid document ID before requiring a session', () {
      expect(
        () => ApiReportRepository().createReport(
          validReport,
          documentId: 'REP/001',
        ),
        throwsA(isA<ReportStoreException>()),
      );
    });

    test('rejects invalid updates before requiring a session', () {
      expect(
        () => ApiReportRepository().updateReport(
          'REP001',
          const HealthReportDraft(
            id: 'REP001',
            equipment: 'Monitor cardiaco',
            description: 'Falla de encendido',
            priority: 'Urgente',
          ),
        ),
        throwsA(isA<ReportStoreException>()),
      );
    });
  });
}
