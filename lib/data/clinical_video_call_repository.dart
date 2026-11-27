import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/demo_video_call_service.dart';
import 'supabase_config.dart';

class ClinicalVideoCall {
  const ClinicalVideoCall({
    required this.id,
    required this.staffUid,
    required this.patientUid,
    required this.roomName,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  static final _roomPattern = RegExp(r'^BioMedicaDemo-[A-Za-z0-9_-]{24}$');

  final String id;
  final String staffUid;
  final String patientUid;
  final String roomName;
  final String status;
  final DateTime expiresAt;
  final DateTime createdAt;

  String get inviteUrl => Uri.https('meet.jit.si', '/$roomName').toString();

  factory ClinicalVideoCall.fromMap(Map<String, dynamic> row) {
    final id = row['id'];
    final staffUid = row['staff_uid'];
    final patientUid = row['patient_uid'];
    final roomName = row['room_name'];
    final status = row['status'];
    final expiresAt = row['expires_at'];
    final createdAt = row['created_at'];
    if (id is! String ||
        staffUid is! String ||
        patientUid is! String ||
        roomName is! String ||
        !_roomPattern.hasMatch(roomName) ||
        status is! String ||
        !const {'ringing', 'accepted', 'declined', 'ended', 'expired'}
            .contains(status) ||
        expiresAt is! String ||
        createdAt is! String) {
      throw const ClinicalVideoCallException(
        'La invitación de llamada no tiene un formato válido.',
      );
    }
    return ClinicalVideoCall(
      id: id,
      staffUid: staffUid,
      patientUid: patientUid,
      roomName: roomName,
      status: status,
      expiresAt: DateTime.parse(expiresAt),
      createdAt: DateTime.parse(createdAt),
    );
  }
}

abstract interface class ClinicalVideoCallRepository {
  Future<ClinicalVideoCall> createCall(String patientUid);

  Stream<List<ClinicalVideoCall>> watchIncomingCalls();

  Future<void> respondToCall(String callId, {required bool accept});
}

class SupabaseClinicalVideoCallRepository
    implements ClinicalVideoCallRepository {
  SupabaseClinicalVideoCallRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ClinicalVideoCallException(
        'El servicio de llamadas no está disponible. Inténtalo más tarde.',
      );
    }
    return Supabase.instance.client;
  }

  @override
  Future<ClinicalVideoCall> createCall(String patientUid) async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const ClinicalVideoCallException(
        'Inicia sesión para comenzar una llamada.',
      );
    }
    if (patientUid.isEmpty) {
      throw const ClinicalVideoCallException(
        'Selecciona un paciente para iniciar la llamada.',
      );
    }
    final invite = DemoVideoCallService.createInvite();
    try {
      final result = await supabaseClient.rpc(
        'create_clinical_video_call',
        params: {
          'target_patient_uid': patientUid,
          'target_room_name': invite.pathSegments.single,
        },
      );
      if (result is! Map) {
        throw const ClinicalVideoCallException(
          'No se pudo enviar la invitación. Inténtalo de nuevo.',
        );
      }
      return ClinicalVideoCall.fromMap(Map<String, dynamic>.from(result));
    } on PostgrestException catch (error) {
      debugPrint(
        'Clinical call creation failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      if (error.code == '23505') {
        throw const ClinicalVideoCallException(
          'Ya hay una invitación activa para este paciente. Espera a que '
          'termine o expire antes de iniciar otra.',
        );
      }
      throw const ClinicalVideoCallException(
        'No se pudo enviar la invitación. Verifica que el paciente esté '
        'asignado y vuelve a intentarlo.',
      );
    }
  }

  @override
  Stream<List<ClinicalVideoCall>> watchIncomingCalls() {
    final patientUid = supabaseClient.auth.currentUser?.id;
    if (patientUid == null) {
      throw const ClinicalVideoCallException(
        'Inicia sesión para recibir llamadas.',
      );
    }
    return supabaseClient
        .from('clinical_video_calls')
        .stream(primaryKey: const ['id'])
        .eq('patient_uid', patientUid)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map(ClinicalVideoCall.fromMap)
              .where(
                (call) =>
                    call.status == 'ringing' &&
                    call.expiresAt.isAfter(DateTime.now()),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<void> respondToCall(
    String callId, {
    required bool accept,
  }) async {
    try {
      await supabaseClient.rpc(
        'respond_clinical_video_call',
        params: {
          'target_call_uid': callId,
          'target_response': accept ? 'accepted' : 'declined',
        },
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'Clinical call response failed '
        '(database code: ${error.code ?? 'unknown'}).',
      );
      throw ClinicalVideoCallException(
        accept
            ? 'La invitación expiró o ya no está disponible. Solicita otra.'
            : 'No se pudo rechazar la invitación. Inténtalo de nuevo.',
      );
    }
  }
}

class ClinicalVideoCallException implements Exception {
  const ClinicalVideoCallException(this.message);

  final String message;

  @override
  String toString() => message;
}
