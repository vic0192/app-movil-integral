import 'package:biomedica_app/models/health_reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MedicationReminderDraft', () {
    test('accepts a valid medication schedule', () {
      final draft = MedicationReminderDraft(
        medicationName: 'Medicamento de prueba',
        dose: '1 tableta',
        intervalHours: 8,
        firstDoseTime: const TimeOfDay(hour: 7, minute: 30),
      );

      expect(draft.validate(), isNull);
    });

    test('rejects empty names and unsupported intervals', () {
      final emptyName = MedicationReminderDraft(
        medicationName: '  ',
        dose: null,
        intervalHours: 8,
        firstDoseTime: const TimeOfDay(hour: 7, minute: 0),
      );
      final invalidInterval = MedicationReminderDraft(
        medicationName: 'Medicamento',
        dose: null,
        intervalHours: 5,
        firstDoseTime: const TimeOfDay(hour: 7, minute: 0),
      );

      expect(emptyName.validate(), contains('nombre'));
      expect(invalidInterval.validate(), contains('frecuencia'));
    });

    test('expands a six-hour interval across midnight', () {
      const medication = MedicationReminder(
        id: 'reminder-id',
        ownerUid: 'owner-id',
        medicationName: 'Medicamento',
        intervalHours: 6,
        firstDoseTime: TimeOfDay(hour: 23, minute: 30),
        timezoneName: 'America/Mexico_City',
        enabled: true,
      );

      expect(medication.dailyTimes, const [
        TimeOfDay(hour: 23, minute: 30),
        TimeOfDay(hour: 5, minute: 30),
        TimeOfDay(hour: 11, minute: 30),
        TimeOfDay(hour: 17, minute: 30),
      ]);
    });
  });

  test('parses Supabase time columns and rejects invalid hours', () {
    final settings = MeasurementReminderSettings.fromMap({
      'owner_uid': 'owner-id',
      'interval_hours': 12,
      'first_measurement_time': '08:15:00',
      'timezone_name': 'America/Mexico_City',
      'enabled': true,
    });

    expect(settings.firstMeasurementTime, const TimeOfDay(hour: 8, minute: 15));
    expect(
      () => MeasurementReminderSettings.fromMap({
        'owner_uid': 'owner-id',
        'interval_hours': 12,
        'first_measurement_time': '25:15:00',
        'timezone_name': 'America/Mexico_City',
        'enabled': true,
      }),
      throwsFormatException,
    );
  });
}
