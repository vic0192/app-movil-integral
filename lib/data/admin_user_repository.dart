import 'package:flutter/foundation.dart';
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

  Stream<List<DoctorCredentialRequest>> watchDoctorApplications() async* {
    while (true) {
      await _ensureAdmin();
      yield await _fetchDoctorApplications();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  Future<List<DoctorCredentialRequest>> _fetchDoctorApplications() async {
    try {
      final rows = await supabaseClient
          .from('doctor_credentials')
          .select(
            'doctor_uid, professional_license, specialty, specialty_license, '
            'institution, contact_phone, created_at',
          )
          .eq('verification_status', 'pending')
          .order('created_at', ascending: false);
      return rows
          .map(DoctorCredentialRequest.fromMap)
          .toList(growable: false);
    } on PostgrestException catch (error) {
      debugPrint(
        'Doctor applications query failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudieron cargar las solicitudes de médicos.',
      );
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
      debugPrint(
        'Admin users query failed (database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudieron cargar las cuentas. Inténtalo más tarde.',
      );
    }
  }

  Future<void> updateRole(String uid, AppRole role) async {
    await _ensureAdmin();
    if (uid == _currentAdminUid) {
      throw const AdminUserException(
        'No puedes cambiar tu propio rol de administrador.',
      );
    }
    if (role == AppRole.doctor) {
      throw const AdminUserException(
        'El rol médico solo se asigna al verificar una solicitud profesional.',
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
      debugPrint(
        'Admin role update failed (database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudo actualizar el rol. Verifica los permisos e inténtalo de nuevo.',
      );
    }
  }

  Future<void> reviewDoctorApplication(
    String doctorUid, {
    required bool approve,
    String? notes,
  }) async {
    await _ensureAdmin();
    try {
      await supabaseClient.rpc(
        'review_doctor_registration',
        params: {
          'target_doctor_uid': doctorUid,
          'target_decision': approve ? 'verified' : 'rejected',
          'target_notes': notes?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Doctor application review failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudo revisar la solicitud. Actualiza la lista e inténtalo de nuevo.',
      );
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
      debugPrint(
        'Doctor assignments update failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudieron guardar las asignaciones. Verifica los permisos e inténtalo de nuevo.',
      );
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
      debugPrint(
        'Admin access check failed (database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminUserException(
        'No se pudo validar el acceso de administrador.',
      );
    }
  }
}

class DoctorCredentialRequest {
  const DoctorCredentialRequest({
    required this.doctorUid,
    required this.professionalLicense,
    required this.specialty,
    required this.specialtyLicense,
    required this.institution,
    required this.contactPhone,
    required this.createdAt,
  });

  final String doctorUid;
  final String professionalLicense;
  final String? specialty;
  final String? specialtyLicense;
  final String? institution;
  final String? contactPhone;
  final DateTime createdAt;

  factory DoctorCredentialRequest.fromMap(Map<String, dynamic> row) {
    final doctorUid = row['doctor_uid'];
    final professionalLicense = row['professional_license'];
    final createdAt = row['created_at'];
    if (doctorUid is! String ||
        professionalLicense is! String ||
        createdAt is! String) {
      throw const AdminUserException(
        'Una solicitud profesional tiene datos incompletos.',
      );
    }
    return DoctorCredentialRequest(
      doctorUid: doctorUid,
      professionalLicense: professionalLicense,
      specialty: row['specialty'] as String?,
      specialtyLicense: row['specialty_license'] as String?,
      institution: row['institution'] as String?,
      contactPhone: row['contact_phone'] as String?,
      createdAt: DateTime.parse(createdAt),
    );
  }
}

class AdminUserException implements Exception {
  const AdminUserException(this.message);

  final String message;

  @override
  String toString() => message;
}
