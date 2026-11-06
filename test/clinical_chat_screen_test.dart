import 'dart:async';

import 'package:biomedica_app/data/clinical_chat_repository.dart';
import 'package:biomedica_app/screens/mi_consulta_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeClinicalChatRepository repository;

  setUp(() => repository = _FakeClinicalChatRepository());
  tearDown(() => repository.close());

  testWidgets('patient opens an assigned doctor chat and sends a message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MiConsultaScreen(patientUid: 'patient-1', repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dra. Ana Torres'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir chat'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Necesito consultar mi reporte.',
    );
    await tester.tap(find.byTooltip('Enviar mensaje'));
    await tester.pumpAndSettle();

    expect(repository.messages, hasLength(1));
    expect(repository.messages.single.body, 'Necesito consultar mi reporte.');
    expect(find.text('Necesito consultar mi reporte.'), findsOneWidget);
  });

  testWidgets('patient sees a clear error when chat creation fails', (
    tester,
  ) async {
    repository.createError = const ClinicalChatException(
      'No se pudo iniciar la conversación.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MiConsultaScreen(patientUid: 'patient-1', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir chat'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo iniciar la conversación.'), findsOneWidget);
    expect(repository.messages, isEmpty);
  });

  testWidgets(
    'chat renders old messages first and new messages at the bottom',
    (tester) async {
      repository.messages.addAll([
        ClinicalMessage(
          id: 'old-message',
          conversationId: 'conversation-1',
          senderUid: 'doctor-1',
          type: 'chat',
          body: 'Mensaje antiguo',
          createdAt: DateTime.utc(2026, 11, 5, 10),
        ),
        ClinicalMessage(
          id: 'new-message',
          conversationId: 'conversation-1',
          senderUid: 'patient-1',
          type: 'chat',
          body: 'Mensaje nuevo',
          createdAt: DateTime.utc(2026, 11, 5, 11),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: MiConsultaScreen(
            patientUid: 'patient-1',
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir chat'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Mensaje antiguo')).dy,
        lessThan(tester.getTopLeft(find.text('Mensaje nuevo')).dy),
      );
    },
  );
}

class _FakeClinicalChatRepository implements ClinicalChatRepository {
  final _messageController = StreamController<List<ClinicalMessage>>.broadcast(
    sync: true,
  );
  final messages = <ClinicalMessage>[];
  ClinicalChatException? createError;

  @override
  Future<List<AssignedDoctor>> assignedDoctors() async => const [
    AssignedDoctor(
      uid: 'doctor-1',
      name: 'Dra. Ana Torres',
      email: 'ana@example.test',
    ),
  ];

  @override
  Stream<List<ClinicalConversation>> watchConversations() =>
      Stream.value(const []);

  @override
  Stream<List<ClinicalMessage>> watchMessages(String conversationId) async* {
    yield List.unmodifiable(messages);
    yield* _messageController.stream;
  }

  @override
  Future<String> createConversation(String doctorUid) async {
    final error = createError;
    if (error != null) throw error;
    return 'conversation-1';
  }

  @override
  Future<void> sendMessage(
    String conversationId,
    String body, {
    String type = 'chat',
    String? attachmentPath,
  }) async {
    messages.add(
      ClinicalMessage(
        id: 'message-${messages.length + 1}',
        conversationId: conversationId,
        senderUid: 'patient-1',
        type: type,
        body: body,
        createdAt: DateTime(2026, 11, 5),
        attachmentPath: attachmentPath,
      ),
    );
    _messageController.add(List.unmodifiable(messages));
  }

  @override
  Future<String> attachmentUrl(String path) async =>
      'https://example.test/$path';

  Future<void> close() => _messageController.close();
}
