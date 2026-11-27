import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/admin_clinic_turn_repository.dart';
import '../models/app_user_profile.dart';

class AdminClinicTurnsSection extends StatefulWidget {
  const AdminClinicTurnsSection({
    super.key,
    required this.patients,
    this.repository,
  });

  final List<AppUserProfile> patients;
  final AdminClinicTurnRepository? repository;

  @override
  State<AdminClinicTurnsSection> createState() =>
      _AdminClinicTurnsSectionState();
}

class _AdminClinicTurnsSectionState extends State<AdminClinicTurnsSection> {
  late final AdminClinicTurnRepository _repository =
      widget.repository ?? SupabaseAdminClinicTurnRepository();
  late final Stream<List<AdminClinicTurn>> _turns = _repository.watchTurns();
  bool _busy = false;

  Future<void> _createTurn() async {
    final draft = await showDialog<_ClinicTurnDraft>(
      context: context,
      builder: (context) => _ClinicTurnDialog(patients: widget.patients),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final turn = await _repository.createTurn(
        patientUid: draft.patientUid,
        service: draft.service,
        room: draft.room,
        priority: draft.priority,
        etaMinutes: draft.etaMinutes,
      );
      _message('Turno ${turn.ticketCode} creado.');
    } on AdminClinicTurnException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudo crear el turno. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(AdminClinicTurn turn, String status) async {
    setState(() => _busy = true);
    try {
      await _repository.updateStatus(turn.id, status);
      _message('Estado del turno ${turn.ticketCode} actualizado.');
    } on AdminClinicTurnException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudo actualizar el turno. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Administrar turnos',
                  style: TextStyle(
                    color: BioMedicaColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy || widget.patients.isEmpty
                    ? null
                    : _createTurn,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuevo turno'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Los códigos de turno se asignan automáticamente para evitar '
            'duplicados.',
            style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (widget.patients.isEmpty)
            const Text(
              'Registra pacientes antes de crear turnos.',
              style: TextStyle(color: BioMedicaColors.muted),
            )
          else
            StreamBuilder<List<AdminClinicTurn>>(
              stream: _turns,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _TurnMessage(
                    'No se pudieron cargar los turnos. Actualiza la página e '
                    'inténtalo de nuevo.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final turns = snapshot.data!;
                if (turns.isEmpty) {
                  return const _TurnMessage('Todavía no hay turnos.');
                }
                final patientsByUid = {
                  for (final patient in widget.patients) patient.uid: patient,
                };
                return Column(
                  children: [
                    for (final turn in turns)
                      _turnTile(turn, patientsByUid[turn.patientUid]),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );

  Widget _turnTile(AdminClinicTurn turn, AppUserProfile? patient) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: BioMedicaColors.primaryLight,
      child: Text(
        turn.ticketCode,
        style: const TextStyle(
          color: BioMedicaColors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    title: Text(turn.service),
    subtitle: Text(
      '${patient?.displayName.isNotEmpty == true ? patient!.displayName : 'Paciente'}'
      ' · ${turn.room} · ${_priorityLabel(turn.priority)}'
      ' · ${turn.etaMinutes} min',
    ),
    trailing: SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        key: ValueKey('turn-status-${turn.id}-${turn.status}'),
        initialValue: turn.status,
        isDense: true,
        decoration: const InputDecoration(
          labelText: 'Estado',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'en_espera', child: Text('En espera')),
          DropdownMenuItem(value: 'en_atencion', child: Text('En atención')),
          DropdownMenuItem(value: 'finalizado', child: Text('Finalizado')),
          DropdownMenuItem(value: 'cancelado', child: Text('Cancelado')),
        ],
        onChanged: _busy
            ? null
            : (status) {
                if (status != null && status != turn.status) {
                  _changeStatus(turn, status);
                }
              },
      ),
    ),
  );

  String _priorityLabel(String priority) => switch (priority) {
    'alta' => 'Prioridad alta',
    'baja' => 'Prioridad baja',
    _ => 'Prioridad media',
  };
}

class _TurnMessage extends StatelessWidget {
  const _TurnMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: BioMedicaColors.muted),
    ),
  );
}

class _ClinicTurnDraft {
  const _ClinicTurnDraft({
    required this.patientUid,
    required this.service,
    required this.room,
    required this.priority,
    required this.etaMinutes,
  });

  final String patientUid;
  final String service;
  final String room;
  final String priority;
  final int etaMinutes;
}

class _ClinicTurnDialog extends StatefulWidget {
  const _ClinicTurnDialog({required this.patients});

  final List<AppUserProfile> patients;

  @override
  State<_ClinicTurnDialog> createState() => _ClinicTurnDialogState();
}

class _ClinicTurnDialogState extends State<_ClinicTurnDialog> {
  final _formKey = GlobalKey<FormState>();
  final _serviceController = TextEditingController();
  final _roomController = TextEditingController();
  final _etaController = TextEditingController(text: '0');
  late String _patientUid = widget.patients.first.uid;
  String _priority = 'media';

  @override
  void dispose() {
    _serviceController.dispose();
    _roomController.dispose();
    _etaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crear turno'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _patientUid,
                decoration: const InputDecoration(labelText: 'Paciente'),
                items: widget.patients
                    .map(
                      (patient) => DropdownMenuItem(
                        value: patient.uid,
                        child: Text(patient.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _patientUid = value);
                },
              ),
              TextFormField(
                controller: _serviceController,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Servicio'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el servicio.'
                    : null,
              ),
              TextFormField(
                controller: _roomController,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Sala'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe la sala.'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Prioridad'),
                items: const [
                  DropdownMenuItem(value: 'alta', child: Text('Alta')),
                  DropdownMenuItem(value: 'media', child: Text('Media')),
                  DropdownMenuItem(value: 'baja', child: Text('Baja')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              TextFormField(
                controller: _etaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiempo estimado (minutos)',
                ),
                validator: (value) {
                  final minutes = int.tryParse(value ?? '');
                  if (minutes == null || minutes < 0 || minutes > 1440) {
                    return 'Escribe un valor entre 0 y 1440 minutos.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Crear turno'),
      ),
    ],
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ClinicTurnDraft(
        patientUid: _patientUid,
        service: _serviceController.text.trim(),
        room: _roomController.text.trim(),
        priority: _priority,
        etaMinutes: int.parse(_etaController.text.trim()),
      ),
    );
  }
}
