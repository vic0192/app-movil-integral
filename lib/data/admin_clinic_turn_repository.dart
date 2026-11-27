import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import 'supabase_config.dart';

class AdminClinicTurn {
  const AdminClinicTurn({
    required this.id,
    required this.ticketCode,
    required this.patientUid,
    required this.service,
    required this.room,
    required this.priority,
    required this.status,
    required this.etaMinutes,
    required this.createdAt,
  });

  final String id;
  final String ticketCode;
  final String patientUid;
  final String service;
  final String room;
  final String priority;
  final String status;
  final int etaMinutes;
  final DateTime createdAt;

  factory AdminClinicTurn.fromMap(Map<String, dynamic> row) {
    final id = row['id'];
    final ticketCode = row['ticket_code'];
    final patientUid = row['patient_uid'];
    final service = row['service'];
    final room = row['room'];
    final priority = row['priority'];
    final status = row['status'];
    final etaMinutes = row['eta_minutes'];
    final createdAt = row['created_at'];
    if (id is! String ||
        ticketCode is! String ||
        patientUid is! String ||
        service is! String ||
        room is! String ||
        !const {'alta', 'media', 'baja'}.contains(priority) ||
        !const {'en_espera', 'en_atencion', 'finalizado', 'cancelado'}
            .contains(status) ||
        etaMinutes is! num ||
        createdAt is! String) {
      throw const AdminClinicTurnException(
        'La lista de turnos no tiene un formato válido.',
      );
    }
    return AdminClinicTurn(
      id: id,
      ticketCode: ticketCode,
      patientUid: patientUid,
      service: service,
      room: room,
      priority: priority as String,
      status: status as String,
      etaMinutes: etaMinutes.round(),
      createdAt: DateTime.parse(createdAt),
    );
  }
}

abstract interface class AdminClinicTurnRepository {
  Stream<List<AdminClinicTurn>> watchTurns();

  Future<AdminClinicTurn> createTurn({
    required String patientUid,
    required String service,
    required String room,
    required String priority,
    required int etaMinutes,
  });

  Future<void> updateStatus(String turnId, String status);
}

class SupabaseAdminClinicTurnRepository
    implements AdminClinicTurnRepository {
  SupabaseAdminClinicTurnRepository({this.client});

  final SupabaseClient? client;
  String? _adminUid;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const AdminClinicTurnException(
        'El servicio de turnos no está disponible. Inténtalo más tarde.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Stream<List<AdminClinicTurn>> watchTurns() async* {
    await _ensureAdmin();
    yield* supabaseClient
        .from('clinic_turns')
        .stream(primaryKey: const ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map(AdminClinicTurn.fromMap)
              .toList(growable: false),
        );
  }

  @override
  Future<AdminClinicTurn> createTurn({
    required String patientUid,
    required String service,
    required String room,
    required String priority,
    required int etaMinutes,
  }) async {
    await _ensureAdmin();
    try {
      final result = await supabaseClient.rpc(
        'create_clinic_turn',
        params: {
          'target_patient_uid': patientUid,
          'target_service': service.trim(),
          'target_room': room.trim(),
          'target_priority': priority,
          'target_eta_minutes': etaMinutes,
        },
      );
      if (result is! Map) {
        throw const AdminClinicTurnException(
          'No se pudo confirmar la creación del turno. Actualiza la lista.',
        );
      }
      return AdminClinicTurn.fromMap(Map<String, dynamic>.from(result));
    } on PostgrestException catch (error) {
      debugPrint(
        'Clinic turn creation failed (database code: ${error.code ?? 'unknown'}).',
      );
      throw AdminClinicTurnException.fromDatabaseCode(error.code);
    }
  }

  @override
  Future<void> updateStatus(String turnId, String status) async {
    await _ensureAdmin();
    if (!const {'en_espera', 'en_atencion', 'finalizado', 'cancelado'}
        .contains(status)) {
      throw const AdminClinicTurnException(
        'Selecciona un estado válido para el turno.',
      );
    }
    try {
      final result = await supabaseClient
          .from('clinic_turns')
          .update({'status': status})
          .eq('id', turnId)
          .select('id')
          .maybeSingle();
      if (result == null) {
        throw const AdminClinicTurnException(
          'No se encontró el turno o ya no está disponible.',
        );
      }
    } on PostgrestException catch (error) {
      debugPrint(
        'Clinic turn update failed (database code: ${error.code ?? 'unknown'}).',
      );
      throw AdminClinicTurnException.fromDatabaseCode(error.code);
    }
  }

  Future<void> _ensureAdmin() async {
    if (_adminUid != null) return;
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const AdminClinicTurnException(
        'Inicia sesión con una cuenta de administrador.',
      );
    }
    try {
      final profile = await supabaseClient
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != AppRole.admin.name) {
        throw const AdminClinicTurnException(
          'Esta acción requiere una cuenta de administrador.',
        );
      }
      _adminUid = user.id;
    } on PostgrestException catch (error) {
      debugPrint(
        'Clinic turn access check failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      throw const AdminClinicTurnException(
        'No se pudo validar el acceso a la administración de turnos.',
      );
    }
  }
}

class AdminClinicTurnException implements Exception {
  const AdminClinicTurnException(this.message);

  final String message;

  factory AdminClinicTurnException.fromDatabaseCode(String? code) {
    if (code == '23505') {
      return const AdminClinicTurnException(
        'No se pudo asignar un código de turno único. Actualiza la lista e '
        'inténtalo de nuevo.',
      );
    }
    if (code == '42501') {
      return const AdminClinicTurnException(
        'No tienes permiso para modificar este turno.',
      );
    }
    return const AdminClinicTurnException(
      'No se pudo completar la operación de turnos. Actualiza la lista e '
      'inténtalo de nuevo.',
    );
  }

  @override
  String toString() => message;
}
