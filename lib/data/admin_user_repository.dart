import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import 'supabase_config.dart';

class AdminUserRepository {
  AdminUserRepository({this.client});

  final SupabaseClient? client;
  String? _currentAdminUid;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const AdminUserException(
        'Configura Supabase para administrar usuarios.',
      );
    }
    return Supabase.instance.client;
  }

  Stream<List<AppUserProfile>> watchUsers() async* {
    while (true) {
      await _ensureAdmin();
      yield await _fetchUsers();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  Future<List<AppUserProfile>> _fetchUsers() async {
    try {
      final profiles = await supabaseClient
          .from('profiles')
          .select(
            'id, email, first_name, last_name, date_of_birth, '
            'chronic_conditions, other_chronic_condition, role',
          )
          .order('first_name');
      final assignments = await supabaseClient
          .from('doctor_patient_assignments')
          .select('doctor_uid, patient_uid');
      final patientsByDoctor = <String, List<String>>{};
      for (final assignment in assignments) {
        final doctorUid = assignment['doctor_uid'] as String;
        patientsByDoctor
            .putIfAbsent(doctorUid, () => [])
            .add(assignment['patient_uid'] as String);
      }
      return profiles
          .map(
            (profile) => AppUserProfile.fromMap(profile['id'] as String, {
              ...profile,
              'assignedPatientUids':
                  patientsByDoctor[profile['id']] ?? const <String>[],
            }),
          )
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw AdminUserException(error.message);
    }
  }

  Future<void> updateRole(String uid, AppRole role) async {
    await _ensureAdmin();
    if (uid == _currentAdminUid) {
      throw const AdminUserException(
        'No puedes cambiar tu propio rol de administrador.',
      );
    }
    try {
      final result = await supabaseClient
          .from('profiles')
          .update({'role': role.name})
          .eq('id', uid)
          .select('id')
          .maybeSingle();
      if (result == null) {
        throw const AdminUserException(
          'No se encontró el usuario o no tienes permiso para cambiar su rol.',
        );
      }
    } on PostgrestException catch (error) {
      throw AdminUserException(error.message);
    }
  }

  Future<void> updateDoctorAssignments(
    String doctorUid,
    List<String> patientUids,
  ) async {
    await _ensureAdmin();
    final uniquePatientUids = patientUids.toSet().toList(growable: false);
    if (uniquePatientUids.length > 30) {
      throw const AdminUserException(
        'Un médico puede tener como máximo 30 pacientes asignados.',
      );
    }
    try {
      await supabaseClient.rpc(
        'replace_doctor_assignments',
        params: {
          'target_doctor_uid': doctorUid,
          'target_patient_uids': uniquePatientUids,
        },
      );
    } on PostgrestException catch (error) {
      throw AdminUserException(error.message);
    }
  }

  Future<void> _ensureAdmin() async {
    if (_currentAdminUid != null) return;
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const AdminUserException(
        'Inicia sesión con una cuenta de administrador.',
      );
    }
    try {
      final profile = await supabaseClient
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != 'admin') {
        throw const AdminUserException(
          'Inicia sesión con una cuenta de administrador.',
        );
      }
      _currentAdminUid = user.id;
    } on PostgrestException catch (error) {
      throw AdminUserException(error.message);
    }
  }
}

class AdminUserException implements Exception {
  const AdminUserException(this.message);

  final String message;

  @override
  String toString() => message;
}
