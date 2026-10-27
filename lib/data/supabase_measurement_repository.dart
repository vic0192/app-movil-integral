import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wearable_measurement.dart';
import 'supabase_config.dart';

class SupabaseMeasurementRepository implements MeasurementRepository {
  SupabaseMeasurementRepository({this.client});

  final SupabaseClient? client;
  String? _ownerUid;
  String? _role;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const MeasurementStoreException(
        'Configura Supabase para guardar mediciones.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<void> initialize() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const MeasurementStoreException(
        'Inicia sesión para acceder a las mediciones.',
      );
    }
    final profile = await supabaseClient
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null || profile['role'] is! String) {
      throw const MeasurementStoreException(
        'No se encontró el perfil de esta cuenta en Supabase.',
      );
    }
    _ownerUid = user.id;
    _role = profile['role'] as String;
  }

  @override
  Stream<List<WearableMeasurement>> watchMeasurements() {
    _requireOwner();
    return supabaseClient
        .from('measurements')
        .stream(primaryKey: ['id'])
        .order('reading_at', ascending: false)
        .map(
          (rows) =>
              rows.map(WearableMeasurement.fromJson).toList(growable: false),
        );
  }

  @override
  Future<String> saveMeasurement(WearableMeasurementDraft measurement) async {
    final validationError = measurement.validate();
    if (validationError != null) {
      throw MeasurementStoreException(validationError);
    }
    final uid = _requireOwner();
    if (_role != 'patient') {
      throw const MeasurementStoreException(
        'Solo los pacientes pueden registrar sus mediciones.',
      );
    }
    try {
      final result = await supabaseClient
          .from('measurements')
          .insert({'owner_uid': uid, ...measurement.toSupabaseMap()})
          .select('id')
          .single();
      return result['id'] as String;
    } on PostgrestException catch (error) {
      throw MeasurementStoreException(error.message, code: error.code);
    }
  }

  String _requireOwner() {
    final uid = _ownerUid;
    if (uid == null) {
      throw const MeasurementStoreException(
        'La sesión de Supabase no está lista. Vuelve a iniciar sesión.',
      );
    }
    return uid;
  }
}

abstract interface class MeasurementRepository {
  Future<void> initialize();

  Stream<List<WearableMeasurement>> watchMeasurements();

  Future<String> saveMeasurement(WearableMeasurementDraft measurement);
}

class MeasurementStoreException implements Exception {
  const MeasurementStoreException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
