import 'dart:async';

import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/clinical_chat_repository.dart';

class MiConsultaScreen extends StatefulWidget {
  const MiConsultaScreen({
    super.key,
    required this.patientUid,
    this.repository,
  });

  final String patientUid;
  final ClinicalChatRepository? repository;

  @override
  State<MiConsultaScreen> createState() => MiConsultaScreenState();
}

class MiConsultaScreenState extends State<MiConsultaScreen> {
  late final ClinicalChatRepository _repository =
      widget.repository ?? SupabaseClinicalChatRepository();
  late Stream<List<ClinicalConversation>> _conversations;
  Stream<List<ClinicalMessage>>? _messages;
  final _messageController = TextEditingController();
  final _messageScrollController = ScrollController();
  final _doctorNames = <String, String>{};
  List<AssignedDoctor> _doctors = const [];
  ClinicalConversation? _selectedConversation;
  String? _latestMessageId;
  String? _error;
  bool _loadingDoctors = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _conversations = _repository.watchConversations();
    unawaited(_loadDoctors());
  }

  Future<void> refresh() async {
    final conversation = _selectedConversation;
    setState(() {
      _error = null;
      _conversations = _repository.watchConversations();
      _messages = conversation == null
          ? null
          : _repository.watchMessages(conversation.id);
      _latestMessageId = null;
    });
    await _loadDoctors();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    try {
      final doctors = await _repository.assignedDoctors();
      if (!mounted) return;
      setState(() {
        _doctors = doctors;
        _doctorNames.addEntries(
          doctors.map((doctor) => MapEntry(doctor.uid, doctor.name)),
        );
        _loadingDoctors = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loadingDoctors = false;
      });
    }
  }

  Future<void> _startConversation(AssignedDoctor doctor) async {
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final id = await _repository.createConversation(doctor.uid);
      if (!mounted) return;
      setState(() {
        _selectedConversation = ClinicalConversation(
          id: id,
          doctorUid: doctor.uid,
          patientUid: widget.patientUid,
          updatedAt: DateTime.now(),
        );
        _messages = _repository.watchMessages(id);
        _latestMessageId = null;
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _sending = false;
      });
    }
  }

  void _openConversation(ClinicalConversation conversation) {
    setState(() {
      _selectedConversation = conversation;
      _messages = _repository.watchMessages(conversation.id);
      _latestMessageId = null;
    });
  }

  Future<void> _sendMessage() async {
    final conversation = _selectedConversation;
    final body = _messageController.text.trim();
    if (conversation == null || body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _repository.sendMessage(conversation.id, body);
      if (!mounted) return;
      _messageController.clear();
      setState(() => _sending = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _selectedConversation;
    return Scaffold(
      backgroundColor: BioMedicaColors.canvas,
      appBar: AppBar(
        title: Text(conversation == null ? 'Mi consulta' : 'Chat médico'),
        leading: conversation == null
            ? null
            : IconButton(
                tooltip: 'Volver a conversaciones',
                onPressed: () => setState(() => _selectedConversation = null),
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      body: conversation == null
          ? _conversationList()
          : _conversationThread(conversation),
    );
  }

  Widget _conversationList() => StreamBuilder<List<ClinicalConversation>>(
    stream: _conversations,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _messageState('No se pudieron cargar las conversaciones: ${snapshot.error}');
      }
      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
        return _scrollState(const CircularProgressIndicator());
      }
      final conversations = snapshot.data ?? const <ClinicalConversation>[];
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Comunícate de forma privada con el equipo médico asignado.',
            style: TextStyle(color: BioMedicaColors.muted),
          ),
          if (_error != null) _errorBanner(_error!),
          const SizedBox(height: 16),
          const Text(
            'Médicos asignados',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_loadingDoctors)
            const LinearProgressIndicator()
          else if (_doctors.isEmpty)
            const Text(
              'Aún no tienes un médico asignado. Solicita apoyo al administrador.',
              style: TextStyle(color: BioMedicaColors.muted),
            )
          else
            for (final doctor in _doctors)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.medical_services_outlined),
                  ),
                  title: Text(doctor.name.isEmpty ? 'Médico asignado' : doctor.name),
                  subtitle: Text(doctor.email),
                  trailing: IconButton(
                    tooltip: 'Abrir chat',
                    onPressed: _sending ? null : () => _startConversation(doctor),
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                ),
              ),
          const SizedBox(height: 16),
          const Text(
            'Conversaciones',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (conversations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no tienes conversaciones. Elige un médico asignado para iniciar una.',
                style: TextStyle(color: BioMedicaColors.muted),
              ),
            )
          else
            for (final item in conversations)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.forum_outlined),
                  ),
                  title: Text(_doctorNames[item.doctorUid] ?? 'Médico asignado'),
                  subtitle: Text('Actualizada ${_formatDate(item.updatedAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openConversation(item),
                ),
              ),
        ],
      );
    },
  );

  Widget _conversationThread(ClinicalConversation conversation) => Column(
    children: [
      if (_error != null) _errorBanner(_error!),
      Expanded(
        child: StreamBuilder<List<ClinicalMessage>>(
          stream: _messages ??= _repository.watchMessages(conversation.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _messageState('No se pudieron recibir los mensajes: ${snapshot.error}');
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _scrollState(const CircularProgressIndicator());
            }
            final messages = [...?snapshot.data]
              ..sort((first, second) {
                final chronological = first.createdAt.compareTo(second.createdAt);
                return chronological != 0
                    ? chronological
                    : first.id.compareTo(second.id);
              });
            _scrollToLatestMessage(messages);
            if (messages.isEmpty) {
              return _messageState(
                'Esta conversación está vacía. Escribe un mensaje para comenzar.',
              );
            }
            return ListView.builder(
              controller: _messageScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _messageBubble(messages[index]);
              },
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  maxLength: 4000,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar mensaje',
                onPressed: _sending ? null : _sendMessage,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  void _scrollToLatestMessage(List<ClinicalMessage> messages) {
    if (messages.isEmpty) return;
    final latestId = messages.last.id;
    if (latestId == _latestMessageId) return;
    final shouldFollow = _latestMessageId == null ||
        !_messageScrollController.hasClients ||
        _messageScrollController.position.maxScrollExtent -
                _messageScrollController.position.pixels <
            120;
    _latestMessageId = latestId;
    if (!shouldFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScrollController.hasClients) return;
      _messageScrollController.animateTo(
        _messageScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _messageBubble(ClinicalMessage message) {
    final mine = message.senderUid == widget.patientUid;
    final label = switch (message.type) {
      'clinical_note' => 'Nota médica',
      'prescription_info' => 'Indicaciones médicas',
      _ => null,
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? BioMedicaColors.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            Text(message.body),
            if (message.attachmentPath case final path?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FutureBuilder<String>(
                  future: _repository.attachmentUrl(path),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('No se pudo cargar la imagen adjunta.');
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Image.network(
                      snapshot.data!,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('No se pudo cargar la imagen adjunta.'),
                    );
                  },
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatDate(message.createdAt),
              style: const TextStyle(fontSize: 10, color: BioMedicaColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageState(String message) => _scrollState(
    Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: BioMedicaColors.muted),
    ),
  );

  Widget _scrollState(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );

  Widget _errorBanner(String message) => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEBEE),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message, style: const TextStyle(color: Colors.red)),
  );

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
