import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_reminders.dart';
import 'supabase_config.dart';

abstract interface class ReminderRepository {
  Future<List<MedicationReminder>> loadMedicationReminders();

  Future<MedicationReminder> saveMedicationReminder(
    MedicationReminderDraft draft,
  );

  Future<void> deleteMedicationReminder(String id);

  Future<MeasurementReminderSettings?> loadMeasurementSettings();

  Future<MeasurementReminderSettings> saveMeasurementSettings(
    MeasurementReminderDraft draft,
  );
}

class SupabaseReminderRepository implements ReminderRepository {
  SupabaseReminderRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ReminderStoreException(
        'Configura Supabase para guardar los recordatorios.',
      );
    }
    return Supabase.instance.client;
  }

  String get _ownerUid {
    final uid = supabaseClient.auth.currentUser?.id;
    if (uid == null) {
      throw const ReminderStoreException(
        'Inicia sesión para administrar tus recordatorios.',
      );
    }
    return uid;
  }

  @override
  Future<List<MedicationReminder>> loadMedicationReminders() async {
    try {
      final rows = await supabaseClient
          .from('medication_reminders')
          .select()
          .eq('owner_uid', _ownerUid)
          .order('medication_name');
      return rows.map(MedicationReminder.fromMap).toList(growable: false);
    } on PostgrestException catch (error) {
      throw ReminderStoreException(error.message);
    }
  }

  @override
  Future<MedicationReminder> saveMedicationReminder(
    MedicationReminderDraft draft,
  ) async {
    final validation = draft.validate();
    if (validation != null) throw ReminderStoreException(validation);
    final timezoneName = (await FlutterTimezone.getLocalTimezone()).identifier;
    final record = <String, Object?>{
      'owner_uid': _ownerUid,
      'medication_name': draft.medicationName.trim(),
      'dose': (draft.dose?.trim().isEmpty ?? true) ? null : draft.dose!.trim(),
      'interval_hours': draft.intervalHours,
      'first_dose_time': timeOfDayToDatabase(draft.firstDoseTime),
      'timezone_name': timezoneName,
      'enabled': draft.enabled,
      if (draft.id != null) 'id': draft.id,
    };
    try {
      final result = await supabaseClient
          .from('medication_reminders')
          .upsert(record)
          .select()
          .single();
      return MedicationReminder.fromMap(result);
    } on PostgrestException catch (error) {
      throw ReminderStoreException(error.message);
    }
  }

  @override
  Future<void> deleteMedicationReminder(String id) async {
    try {
      await supabaseClient
          .from('medication_reminders')
          .delete()
          .eq('id', id)
          .eq('owner_uid', _ownerUid);
    } on PostgrestException catch (error) {
      throw ReminderStoreException(error.message);
    }
  }

  @override
  Future<MeasurementReminderSettings?> loadMeasurementSettings() async {
    try {
      final result = await supabaseClient
          .from('measurement_reminder_settings')
          .select()
          .eq('owner_uid', _ownerUid)
          .maybeSingle();
      return result == null
          ? null
          : MeasurementReminderSettings.fromMap(result);
    } on PostgrestException catch (error) {
      throw ReminderStoreException(error.message);
    }
  }

  @override
  Future<MeasurementReminderSettings> saveMeasurementSettings(
    MeasurementReminderDraft draft,
  ) async {
    final validation = draft.validate();
    if (validation != null) throw ReminderStoreException(validation);
    final timezoneName = (await FlutterTimezone.getLocalTimezone()).identifier;
    try {
      final result = await supabaseClient
          .from('measurement_reminder_settings')
          .upsert({
            'owner_uid': _ownerUid,
            'interval_hours': draft.intervalHours,
            'first_measurement_time': timeOfDayToDatabase(
              draft.firstMeasurementTime,
            ),
            'timezone_name': timezoneName,
            'enabled': draft.enabled,
          }, onConflict: 'owner_uid')
          .select()
          .single();
      return MeasurementReminderSettings.fromMap(result);
    } on PostgrestException catch (error) {
      throw ReminderStoreException(error.message);
    }
  }
}

class ReminderStoreException implements Exception {
  const ReminderStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
