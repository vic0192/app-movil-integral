import 'package:flutter/material.dart';

class MedicationReminder {
  const MedicationReminder({
    required this.id,
    required this.ownerUid,
    required this.medicationName,
    required this.intervalHours,
    required this.firstDoseTime,
    required this.timezoneName,
    required this.enabled,
    this.dose,
  });

  final String id;
  final String ownerUid;
  final String medicationName;
  final String? dose;
  final int intervalHours;
  final TimeOfDay firstDoseTime;
  final String timezoneName;
  final bool enabled;

  List<TimeOfDay> get dailyTimes {
    if (!const {4, 6, 8, 12, 24}.contains(intervalHours)) {
      throw const FormatException('La frecuencia del medicamento no es válida.');
    }
    final firstMinute = firstDoseTime.hour * 60 + firstDoseTime.minute;
    return List<TimeOfDay>.generate(24 ~/ intervalHours, (index) {
      final minutes = (firstMinute + index * intervalHours * 60) % (24 * 60);
      return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    }, growable: false);
  }

  factory MedicationReminder.fromMap(Map<String, dynamic> data) =>
      MedicationReminder(
        id: data['id'] as String,
        ownerUid: data['owner_uid'] as String,
        medicationName: data['medication_name'] as String,
        dose: data['dose'] as String?,
        intervalHours: (data['interval_hours'] as num).toInt(),
        firstDoseTime: _timeOfDay(data['first_dose_time']),
        timezoneName: data['timezone_name'] as String,
        enabled: data['enabled'] as bool,
      );
}

class MedicationReminderDraft {
  const MedicationReminderDraft({
    this.id,
    required this.medicationName,
    required this.intervalHours,
    required this.firstDoseTime,
    required this.dose,
    this.enabled = true,
  });

  final String? id;
  final String medicationName;
  final String? dose;
  final int intervalHours;
  final TimeOfDay firstDoseTime;
  final bool enabled;

  String? validate() {
    final name = medicationName.trim();
    if (name.isEmpty || name.characters.length > 100) {
      return 'El nombre del medicamento debe tener entre 1 y 100 caracteres.';
    }
    final normalizedDose = dose?.trim() ?? '';
    if (normalizedDose.characters.length > 100) {
      return 'La dosis no puede exceder 100 caracteres.';
    }
    if (!const {4, 6, 8, 12, 24}.contains(intervalHours)) {
      return 'Selecciona una frecuencia válida.';
    }
    return null;
  }
}

class MeasurementReminderSettings {
  const MeasurementReminderSettings({
    required this.ownerUid,
    required this.intervalHours,
    required this.firstMeasurementTime,
    required this.timezoneName,
    required this.enabled,
  });

  final String ownerUid;
  final int intervalHours;
  final TimeOfDay firstMeasurementTime;
  final String timezoneName;
  final bool enabled;

  factory MeasurementReminderSettings.fromMap(Map<String, dynamic> data) =>
      MeasurementReminderSettings(
        ownerUid: data['owner_uid'] as String,
        intervalHours: (data['interval_hours'] as num).toInt(),
        firstMeasurementTime: _timeOfDay(data['first_measurement_time']),
        timezoneName: data['timezone_name'] as String,
        enabled: data['enabled'] as bool,
      );
}

class MeasurementReminderDraft {
  const MeasurementReminderDraft({
    required this.intervalHours,
    required this.firstMeasurementTime,
    required this.enabled,
  });

  final int intervalHours;
  final TimeOfDay firstMeasurementTime;
  final bool enabled;

  String? validate() => const {4, 6, 8, 12, 24}.contains(intervalHours)
      ? null
      : 'Selecciona una frecuencia válida.';
}

TimeOfDay _timeOfDay(Object? value) {
  if (value is! String || !RegExp(r'^\d{2}:\d{2}').hasMatch(value)) {
    throw const FormatException('La hora del recordatorio no es válida.');
  }
  final parts = value.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  if (hour > 23 || minute > 59) {
    throw const FormatException('La hora del recordatorio no es válida.');
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String timeOfDayToDatabase(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:00';
