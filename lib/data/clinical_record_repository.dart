import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/clinical_record_entry.dart';
import 'supabase_config.dart';

class ClinicalRecordRepository {
  ClinicalRecordRepository({this.client});

  final SupabaseClient? client;
  String? _userUid;
  AppRole? _role;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ClinicalRecordException(
        'Configura Supabase para abrir el expediente clínico.',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> initialize() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const ClinicalRecordException(
        'Inicia sesión para consultar el expediente clínico.',
      );
    }
    final profile = await supabaseClient
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    final roleName = profile?['role'];
    if (roleName is! String) {
      throw const ClinicalRecordException(
        'No se encontró el perfil de esta cuenta en Supabase.',
      );
    }
    _userUid = user.id;
    _role = AppRole.values.firstWhere(
      (role) => role.name == roleName,
      orElse: () => throw const ClinicalRecordException(
        'El perfil no tiene un rol válido.',
      ),
    );
  }

  Future<List<ClinicalRecordPatient>> loadPatients() async {
    final uid = _requireUser();
    try {
      if (_role == AppRole.patient) {
        final patient = await supabaseClient
            .from('profiles')
            .select(
              'id,email,first_name,last_name,date_of_birth,chronic_conditions,'
              'other_chronic_condition,role',
            )
            .eq('id', uid)
            .maybeSingle();
        return patient == null
            ? const []
            : [AppUserProfile.fromMap(uid, patient)];
      }

      if (_role == AppRole.doctor) {
        final assignments = await supabaseClient
            .from('doctor_patient_assignments')
            .select('patient_uid')
            .eq('doctor_uid', uid);
        final patientUids = assignments
            .map((row) => row['patient_uid'] as String)
            .toList(growable: false);
        if (patientUids.isEmpty) return const [];
        final profiles = await supabaseClient
            .from('profiles')
            .select(
              'id,email,first_name,last_name,date_of_birth,chronic_conditions,'
              'other_chronic_condition,role',
            )
            .inFilter('id', patientUids);
        return profiles
            .map(
              (profile) => AppUserProfile.fromMap(
                profile['id'] as String,
                profile,
              ),
            )
            .toList(growable: false);
      }

      final profiles = await supabaseClient
          .from('profiles')
          .select(
            'id,email,first_name,last_name,date_of_birth,chronic_conditions,'
            'other_chronic_condition,role',
          )
          .eq('role', 'patient')
          .order('first_name');
      return profiles
          .map(
            (profile) =>
                AppUserProfile.fromMap(profile['id'] as String, profile),
          )
          .toList(growable: false);
    } on PostgrestException {
      throw const ClinicalRecordException(
        'No se pudieron cargar los pacientes autorizados. Inténtalo de nuevo.',
      );
    }
  }

  Stream<List<ClinicalRecordEntry>> watchEntries(String patientUid) {
    _requireUser();
    if (patientUid.isEmpty) {
      throw const ClinicalRecordException('Selecciona un paciente.');
    }
    return supabaseClient
        .from('clinical_record_entries')
        .stream(primaryKey: ['id'])
        .eq('patient_uid', patientUid)
        .order('occurred_at', ascending: false)
        .map(
          (rows) => rows
              .map(ClinicalRecordEntry.fromMap)
              .toList(growable: false),
        );
  }

  Future<void> addEntry(ClinicalRecordDraft draft) async {
    final authorUid = _requireUser();
    if (_role != AppRole.doctor) {
      throw const ClinicalRecordException(
        'Solo un médico asignado puede añadir entradas al expediente.',
      );
    }
    final validationError = draft.validate();
    if (validationError != null) throw ClinicalRecordException(validationError);
    try {
      await supabaseClient.from('clinical_record_entries').insert({
        'patient_uid': draft.patientUid,
        'author_uid': authorUid,
        'entry_type': draft.type.value,
        'title': draft.title.trim(),
        'details': draft.details.trim(),
        'occurred_at': draft.occurredAt.toUtc().toIso8601String(),
      });
    } on PostgrestException {
      throw const ClinicalRecordException(
        'No se pudo guardar la entrada clínica. Inténtalo de nuevo.',
      );
    }
  }

  String _requireUser() {
    final uid = _userUid;
    if (uid == null || _role == null) {
      throw const ClinicalRecordException(
        'La sesión todavía no está lista. Vuelve a iniciar sesión.',
      );
    }
    return uid;
  }
}

class ClinicalRecordException implements Exception {
  const ClinicalRecordException(this.message);

  final String message;

  @override
  String toString() => message;
}
