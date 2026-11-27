import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class ClinicTurn {
  const ClinicTurn({
    required this.ticketCode,
    required this.service,
    required this.room,
    required this.status,
    required this.etaMinutes,
    required this.updatedAt,
    this.createdAt,
  });

  final String ticketCode;
  final String service;
  final String room;
  final String status;
  final int etaMinutes;
  final DateTime updatedAt;
  final DateTime? createdAt;

  factory ClinicTurn.fromMap(Map<String, dynamic> row) {
    final ticketCode = row['ticket_code'];
    final service = row['service'];
    final room = row['room'];
    final status = row['status'];
    final etaMinutes = row['eta_minutes'];
    final updatedAt = row['updated_at'];
    if (ticketCode is! String ||
        service is! String ||
        room is! String ||
        status is! String ||
        !const {'en_espera', 'en_atencion'}.contains(status) ||
        etaMinutes is! num ||
        updatedAt is! String) {
      throw const ClinicTurnException(
        'La base de datos devolvió un turno inválido.',
      );
    }
    final createdAt = row['created_at'];
    if (createdAt != null && createdAt is! String) {
      throw const ClinicTurnException(
        'La fecha de creación del turno no es válida.',
      );
    }
    return ClinicTurn(
      ticketCode: ticketCode,
      service: service,
      room: room,
      status: status,
      etaMinutes: etaMinutes.round(),
      updatedAt: DateTime.parse(updatedAt),
      createdAt: createdAt == null ? null : DateTime.parse(createdAt),
    );
  }
}

abstract interface class ClinicTurnRepository {
  Future<ClinicTurn?> loadMyActiveTurn();

  Future<List<ClinicTurn>> loadActiveQueue();
}

class SupabaseClinicTurnRepository implements ClinicTurnRepository {
  SupabaseClinicTurnRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ClinicTurnException(
        'Configura Supabase para consultar los turnos.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<ClinicTurn?> loadMyActiveTurn() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const ClinicTurnException('Inicia sesión para consultar tu turno.');
    }
    try {
      final result = await supabaseClient
          .from('clinic_turns')
          .select(
            'ticket_code, service, room, status, eta_minutes, updated_at, created_at',
          )
          .eq('patient_uid', user.id)
          .inFilter('status', const ['en_espera', 'en_atencion'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return result == null ? null : ClinicTurn.fromMap(result);
    } on PostgrestException {
      throw const ClinicTurnException(
        'No se pudo consultar tu turno. Inténtalo de nuevo.',
      );
    }
  }

  @override
  Future<List<ClinicTurn>> loadActiveQueue() async {
    try {
      final result = await supabaseClient.rpc('public_clinic_turn_feed');
      if (result is! List) {
        throw const ClinicTurnException(
          'Supabase devolvió una lista de turnos inválida.',
        );
      }
      return result
          .whereType<Map>()
          .map((row) => ClinicTurn.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } on PostgrestException {
      throw const ClinicTurnException(
        'No se pudo consultar la lista de turnos. Inténtalo de nuevo.',
      );
    }
  }
}

class ClinicTurnException implements Exception {
  const ClinicTurnException(this.message);

  final String message;

  @override
  String toString() => message;
}
