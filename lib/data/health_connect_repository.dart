import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_connect_record.dart';
import 'supabase_config.dart';

class HealthConnectRepository {
  HealthConnectRepository({this.client});

  final SupabaseClient? client;
  String? _ownerUid;
  String? _role;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const HealthConnectStoreException(
        'Configura Supabase para guardar los datos de salud sincronizados.',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> initialize() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const HealthConnectStoreException(
        'Inicia sesión para consultar tus datos de salud.',
      );
    }
    final profile = await supabaseClient
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null || profile['role'] is! String) {
      throw const HealthConnectStoreException(
        'No se encontró el perfil de esta cuenta en Supabase.',
      );
    }
    _ownerUid = user.id;
    _role = profile['role'] as String;
  }

  Future<void> saveRecords(List<HealthConnectRecord> records) async {
    final ownerUid = _requirePatient();
    for (var start = 0; start < records.length; start += 200) {
      final end = (start + 200).clamp(0, records.length);
      final batch = records
          .sublist(start, end)
          .map((record) => record.toSupabaseMap(ownerUid))
          .toList(growable: false);
      await supabaseClient
          .from('health_connect_records')
          .upsert(
            batch,
            onConflict: 'owner_uid,external_id',
            ignoreDuplicates: true,
          );
    }
  }

  Future<List<HealthConnectRecord>> loadRecentRecords({int limit = 200}) async {
    _requireUser();
    final rows = await supabaseClient
        .from('health_connect_records')
        .select()
        .order('recorded_at', ascending: false)
        .limit(limit);
    return rows
        .map(
          (row) => HealthConnectRecord.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Stream<List<SharedHealthConnectRecord>> watchRecordsForClinicians() {
    _requireUser();
    if (_role == 'patient') {
      throw const HealthConnectStoreException(
        'La vista clínica está disponible para personal autorizado.',
      );
    }
    return supabaseClient
        .from('health_connect_records')
        .stream(primaryKey: ['id'])
        .order('recorded_at', ascending: false)
        .map(
          (rows) => rows
              .map(
                (row) => (
                  patientUid: row['owner_uid'] as String,
                  record: HealthConnectRecord.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                ),
              )
              .toList(growable: false),
        )
        .asyncMap(_includePatientNames);
  }

  Future<List<SharedHealthConnectRecord>> _includePatientNames(
    List<({String patientUid, HealthConnectRecord record})> records,
  ) async {
    if (records.isEmpty) return const [];
    final patientUids = records.map((entry) => entry.patientUid).toSet();
    final profiles = await supabaseClient
        .from('profiles')
        .select('id, first_name, last_name')
        .inFilter('id', patientUids.toList(growable: false));
    final namesByUid = <String, String>{};
    for (final profile in profiles) {
      final uid = profile['id'] as String;
      final firstName = profile['first_name'] as String? ?? '';
      final lastName = profile['last_name'] as String? ?? '';
      namesByUid[uid] = '$firstName $lastName'.trim();
    }
    return records
        .map(
          (entry) => SharedHealthConnectRecord(
            patientUid: entry.patientUid,
            patientName: namesByUid[entry.patientUid] ?? '',
            record: entry.record,
          ),
        )
        .toList(growable: false);
  }

  String _requirePatient() {
    final uid = _requireUser();
    if (_role != 'patient') {
      throw const HealthConnectStoreException(
        'Solo una cuenta de paciente puede importar datos de salud.',
      );
    }
    return uid;
  }

  String _requireUser() {
    final uid = _ownerUid;
    if (uid == null) {
      throw const HealthConnectStoreException(
        'La sesión de Supabase no está lista. Vuelve a iniciar sesión.',
      );
    }
    return uid;
  }
}

class HealthConnectStoreException implements Exception {
  const HealthConnectStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
