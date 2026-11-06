import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core_api_client.dart';
import 'supabase_config.dart';

class AssignedDoctor {
  const AssignedDoctor({
    required this.uid,
    required this.name,
    required this.email,
  });

  final String uid;
  final String name;
  final String email;
}

class ClinicalConversation {
  const ClinicalConversation({
    required this.id,
    required this.doctorUid,
    required this.patientUid,
    required this.updatedAt,
  });

  final String id;
  final String doctorUid;
  final String patientUid;
  final DateTime updatedAt;

  factory ClinicalConversation.fromMap(Map<String, dynamic> row) =>
      ClinicalConversation(
        id: row['id'] as String,
        doctorUid: row['doctor_uid'] as String,
        patientUid: row['patient_uid'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}

class ClinicalMessage {
  const ClinicalMessage({
    required this.id,
    required this.conversationId,
    required this.senderUid,
    required this.type,
    required this.body,
    required this.createdAt,
    this.attachmentPath,
  });

  final String id;
  final String conversationId;
  final String senderUid;
  final String type;
  final String body;
  final DateTime createdAt;
  final String? attachmentPath;

  factory ClinicalMessage.fromMap(Map<String, dynamic> row) => ClinicalMessage(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    senderUid: row['sender_uid'] as String,
    type: row['message_type'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    attachmentPath: row['attachment_path'] as String?,
  );
}

abstract interface class ClinicalChatRepository {
  Future<List<AssignedDoctor>> assignedDoctors();

  Stream<List<ClinicalConversation>> watchConversations();

  Stream<List<ClinicalMessage>> watchMessages(String conversationId);

  Future<String> createConversation(String doctorUid);

  Future<void> sendMessage(
    String conversationId,
    String body, {
    String type = 'chat',
    String? attachmentPath,
  });

  Future<String> attachmentUrl(String path);
}

class SupabaseClinicalChatRepository implements ClinicalChatRepository {
  SupabaseClinicalChatRepository({this.client});

  final SupabaseClient? client;

  SupabaseClient get supabaseClient {
    final injectedClient = client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ClinicalChatException(
        'Configura Supabase para abrir Mi consulta.',
      );
    }
    return Supabase.instance.client;
  }

  String get _patientUid {
    final uid = supabaseClient.auth.currentUser?.id;
    if (uid == null) {
      throw const ClinicalChatException(
        'Inicia sesión para consultar tus conversaciones.',
      );
    }
    return uid;
  }

  @override
  Future<List<AssignedDoctor>> assignedDoctors() async {
    final uid = _patientUid;
    try {
      final assignments = await supabaseClient
          .from('doctor_patient_assignments')
          .select('doctor_uid')
          .eq('patient_uid', uid);
      final doctorUids = assignments
          .map((row) => row['doctor_uid'] as String)
          .toList(growable: false);
      if (doctorUids.isEmpty) return const [];

      final result = <AssignedDoctor>[];
      for (final doctorUid in doctorUids) {
        final profile = await supabaseClient
            .from('profiles')
            .select('id, first_name, last_name, email')
            .eq('id', doctorUid)
            .maybeSingle();
        if (profile == null) continue;
        final firstName = profile['first_name'] as String? ?? '';
        final lastName = profile['last_name'] as String? ?? '';
        result.add(
          AssignedDoctor(
            uid: doctorUid,
            name: '$firstName $lastName'.trim(),
            email: profile['email'] as String? ?? '',
          ),
        );
      }
      return result;
    } on PostgrestException catch (error) {
      throw ClinicalChatException(error.message);
    }
  }

  @override
  Stream<List<ClinicalConversation>> watchConversations() {
    final uid = _patientUid;
    return supabaseClient
        .from('clinical_conversations')
        .stream(primaryKey: ['id'])
        .eq('patient_uid', uid)
        .order('updated_at', ascending: false)
        .map(
          (rows) =>
              rows.map(ClinicalConversation.fromMap).toList(growable: false),
        );
  }

  @override
  Stream<List<ClinicalMessage>> watchMessages(String conversationId) {
    _patientUid;
    return supabaseClient
        .from('clinical_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map(
          (rows) => rows.map(ClinicalMessage.fromMap).toList(growable: false),
        );
  }

  @override
  Future<String> createConversation(String doctorUid) async {
    _patientUid;
    try {
      final id = await supabaseClient.rpc(
        'create_clinical_conversation',
        params: {'target_doctor_uid': doctorUid},
      );
      if (id is! String || id.isEmpty) {
        throw const ClinicalChatException(
          'Supabase no devolvió el identificador de la conversación.',
        );
      }
      return id;
    } on PostgrestException catch (error) {
      throw ClinicalChatException(error.message);
    }
  }

  @override
  Future<void> sendMessage(
    String conversationId,
    String body, {
    String type = 'chat',
    String? attachmentPath,
  }) async {
    _patientUid;
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty || normalizedBody.length > 4000) {
      throw const ClinicalChatException(
        'El mensaje debe tener entre 1 y 4000 caracteres.',
      );
    }
    if (!const {'chat', 'clinical_note', 'prescription_info'}.contains(type)) {
      throw const ClinicalChatException('El tipo de mensaje no es válido.');
    }
    try {
      final inserted = await supabaseClient
          .from('clinical_messages')
          .insert({
            'conversation_id': conversationId,
            'sender_uid': _patientUid,
            'message_type': type,
            'body': normalizedBody,
            ...?(attachmentPath == null
                ? null
                : {'attachment_path': attachmentPath}),
          })
          .select('id')
          .single();
      final messageId = inserted['id'];
      if (messageId is String && messageId.isNotEmpty) {
        await _requestPushNotification(messageId);
      } else {
        debugPrint(
          'El mensaje se guardó, pero no se obtuvo un ID para notificar.',
        );
      }
    } on PostgrestException catch (error) {
      throw ClinicalChatException(error.message);
    }
  }

  Future<void> _requestPushNotification(String messageId) async {
    final activeClient = supabaseClient;
    final api = CoreApiClient(
      accessTokenProvider: () async =>
          activeClient.auth.currentSession?.accessToken,
      accessTokenRefresher: () async {
        final refreshed = await activeClient.auth.refreshSession();
        return refreshed.session?.accessToken;
      },
    );
    try {
      await api.post('/api/chat/notifications', {'messageId': messageId});
    } catch (error, stackTrace) {
      debugPrint(
        'El mensaje se guardó, pero no se pudo enviar el aviso push: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<String> attachmentUrl(String path) async {
    _patientUid;
    try {
      return await supabaseClient.storage
          .from('clinical-attachments')
          .createSignedUrl(path, 300);
    } on StorageException catch (error) {
      throw ClinicalChatException(error.message);
    }
  }
}

class ClinicalChatException implements Exception {
  const ClinicalChatException(this.message);

  final String message;

  @override
  String toString() => message;
}
