import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/health_report.dart';
import 'report_repository.dart';
import 'supabase_config.dart';

export 'report_repository.dart';

class SupabaseReportRepository implements ReportRepository {
  SupabaseReportRepository({this.client});

  final SupabaseClient? client;
  String? _ownerUid;
  AppRole? _role;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ReportStoreException(
        'Configura Supabase para consultar los reportes.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  String? get ownerUid => _ownerUid;

  @override
  AppRole? get role => _role;

  @override
  Future<void> initialize() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const ReportStoreException(
        'Inicia sesión para consultar tus reportes.',
      );
    }
    final profile = await supabaseClient
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null || profile['role'] is! String) {
      throw const ReportStoreException(
        'No se encontró el perfil de esta cuenta en Supabase.',
      );
    }
    _ownerUid = user.id;
    _role = _appRole(profile['role'] as String);
  }

  @override
  Stream<List<HealthReport>> watchReports() {
    _requireOwner();
    return supabaseClient
        .from('equipment_reports')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(HealthReport.fromJson).toList(growable: false));
  }

  @override
  Future<String> createReport(
    HealthReportDraft draft, {
    String? documentId,
  }) async {
    _validateDraft(draft);
    final userId = _requirePatient();
    final id = _validateId(documentId ?? draft.id);
    final record = <String, Object?>{
      'owner_uid': userId,
      'equipment': draft.equipment.trim(),
      'description': draft.description.trim(),
      'priority': draft.priority,
      if (id.isNotEmpty) 'id': id,
    };
    try {
      final result = await supabaseClient
          .from('equipment_reports')
          .insert(record)
          .select('id')
          .single();
      return result['id'] as String;
    } on PostgrestException catch (error) {
      if (error.code == '23505' && id.isNotEmpty) {
        throw DuplicateReportIdException(id);
      }
      throw ReportStoreException(error.message, code: error.code);
    }
  }

  @override
  Future<void> updateReport(String id, HealthReportDraft draft) async {
    _validateDraft(draft);
    _requireWriteAccess();
    final normalizedId = _validateId(id);
    try {
      await supabaseClient
          .from('equipment_reports')
          .update({
            'equipment': draft.equipment.trim(),
            'description': draft.description.trim(),
            'priority': draft.priority,
          })
          .eq('id', normalizedId);
    } on PostgrestException catch (error) {
      throw ReportStoreException(error.message, code: error.code);
    }
  }

  @override
  Future<void> deleteReport(String id) async {
    _requireWriteAccess();
    final normalizedId = _validateId(id);
    try {
      await supabaseClient
          .from('equipment_reports')
          .delete()
          .eq('id', normalizedId);
    } on PostgrestException catch (error) {
      throw ReportStoreException(error.message, code: error.code);
    }
  }

  String _requireOwner() {
    final uid = _ownerUid;
    if (uid == null) {
      throw const ReportStoreException(
        'La sesión de Supabase no está lista. Vuelve a iniciar sesión.',
      );
    }
    return uid;
  }

  String _requirePatient() {
    final uid = _requireOwner();
    if (_role != AppRole.patient) {
      throw const ReportStoreException(
        'Solo una cuenta de paciente puede crear reportes.',
      );
    }
    return uid;
  }

  void _requireWriteAccess() {
    if (_role == AppRole.doctor) {
      throw const ReportStoreException(
        'Los médicos pueden consultar reportes asignados, pero no modificarlos.',
      );
    }
    _requireOwner();
  }

  String _validateId(String value) {
    final normalized = value.trim();
    final error = HealthReportValidation.id(normalized);
    if (error != null) throw ReportStoreException(error);
    return normalized;
  }

  void _validateDraft(HealthReportDraft draft) {
    for (final error in [
      HealthReportValidation.equipment(draft.equipment),
      HealthReportValidation.description(draft.description),
      HealthReportValidation.priority(draft.priority),
    ]) {
      if (error != null) throw ReportStoreException(error);
    }
  }

  AppRole _appRole(String role) => AppRole.values.firstWhere(
    (candidate) => candidate.name == role,
    orElse: () =>
        throw const ReportStoreException('El perfil no tiene un rol válido.'),
  );
}
