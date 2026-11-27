import 'dart:async';

import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/api_report_repository.dart';
import '../data/clinical_record_repository.dart';
import '../data/clinical_video_call_repository.dart';
import '../models/app_user_profile.dart';
import '../models/health_report.dart';
import '../widgets/clinical_call_invite_dialog.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.patientName,
    this.chronicConditions = const [],
    this.repository,
    this.reportsStream,
    this.patientNames,
    this.callRepository,
  });

  final String patientName;
  final List<String> chronicConditions;
  final ReportRepository? repository;
  final Stream<List<HealthReport>>? reportsStream;
  final Map<String, String>? patientNames;
  final ClinicalVideoCallRepository? callRepository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportRepository _repository =
      widget.repository ?? ApiReportRepository();
  late final ClinicalVideoCallRepository _callRepository =
      widget.callRepository ?? SupabaseClinicalVideoCallRepository();
  Stream<List<HealthReport>>? _reports;
  Map<String, String> _patientNames = const {};
  String? _initializationError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _patientNames = widget.patientNames ?? const {};
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportsStream != widget.reportsStream &&
        widget.reportsStream != null) {
      _reports = widget.reportsStream;
      _initializationError = null;
    }
  }

  Future<void> _initialize() async {
    try {
      final reportsStream = widget.reportsStream;
      if (reportsStream != null) {
        if (mounted) setState(() => _reports = reportsStream);
        return;
      }
      await _repository.initialize();
      var patientNames = widget.patientNames ?? const <String, String>{};
      if (widget.patientNames == null && _repository.role != AppRole.patient) {
        try {
          final clinicalRecords = ClinicalRecordRepository();
          await clinicalRecords.initialize();
          final patients = await clinicalRecords.loadPatients();
          patientNames = {
            for (final patient in patients) patient.uid: patient.displayName,
          };
        } catch (error) {
          debugPrint('Could not load report patient labels.');
        }
      }
      if (mounted) {
        setState(() {
          _patientNames = patientNames;
          _reports = _repository.watchReports();
        });
      }
    } on ReportStoreException {
      if (mounted) {
        setState(
          () => _initializationError =
              'No se pudieron cargar los reportes. Inténtalo más tarde.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _initializationError =
              'No se pudo conectar con el servicio de reportes. Inténtalo de nuevo.',
        );
      }
    }
  }

  Future<void> _openForm([HealthReport? report]) async {
    final draft = await showDialog<HealthReportDraft>(
      context: context,
      builder: (_) => _ReportFormDialog(
        report: report,
        chronicConditions: widget.chronicConditions,
      ),
    );
    if (draft == null || !mounted) return;

    try {
      if (report == null) {
        await _createReport(draft);
      } else {
        setState(() => _busy = true);
        await _repository.updateReport(report.id, draft);
        if (mounted) _showMessage('Reporte actualizado.');
      }
    } on ReportStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) {
        _showMessage('No se pudo guardar el reporte. Inténtalo de nuevo.');
      }
    } finally {
      if (report != null && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createReport(HealthReportDraft draft) async {
    setState(() => _busy = true);
    try {
      final id = await _repository.createReport(draft, documentId: draft.id);
      if (mounted) {
        _showMessage('Reporte $id guardado; sincronización en curso.');
      }
    } on ReportStoreException catch (error) {
      if (mounted) {
        _showMessage(
          error.message,
          retry: error.code == 'unavailable' || error.code == 'api-error'
              ? () => unawaited(_createReport(draft))
              : null,
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'No se pudo guardar el reporte. Inténtalo de nuevo.',
          retry: () => unawaited(_createReport(draft)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(HealthReport report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: Text('¿Eliminar el reporte ${report.id}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _repository.deleteReport(report.id);
      if (mounted) _showMessage('Reporte eliminado.');
    } on ReportStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) {
        _showMessage('No se pudo eliminar el reporte. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startCall(HealthReport report) async {
    final patientUid = report.ownerUid;
    if (patientUid == null) {
      _showMessage('Este reporte no tiene un paciente asociado.');
      return;
    }
    setState(() => _busy = true);
    try {
      final call = await _callRepository.createCall(patientUid);
      if (mounted) await showClinicalCallInviteDialog(context, call);
    } on ClinicalVideoCallException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) {
        _showMessage('No se pudo iniciar la llamada. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message, {VoidCallback? retry}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: retry == null
              ? null
              : SnackBarAction(label: 'Reintentar', onPressed: retry),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reportes de salud',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _repository.role == AppRole.patient
                        ? widget.patientName
                        : 'Pacientes autorizados',
                    style: const TextStyle(color: BioMedicaColors.muted),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              key: const ValueKey('newReport'),
              tooltip: 'Nuevo reporte',
              onPressed: _busy || !_canCreate ? null : _openForm,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: _ownerCard(),
      ),
      Expanded(child: _reportList()),
    ],
  );

  bool get _canCreate => _repository.role == AppRole.patient;

  Widget _ownerCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: BioMedicaColors.primaryLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, color: BioMedicaColors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _repository.role == AppRole.patient
                    ? 'Tus reportes de salud'
                    : 'Reportes clínicos de pacientes autorizados',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _reportList() {
    final error = _initializationError;
    if (error != null) {
      return _messageState(
        icon: Icons.cloud_off_rounded,
        message: error,
        action: TextButton.icon(
          onPressed: () => setState(() {
            _initializationError = null;
            _reports = null;
            _initialize();
          }),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      );
    }

    final reports = _reports;
    if (reports == null) {
      return _messageState(
        icon: Icons.hourglass_empty_rounded,
        message: 'Cargando reportes...',
      );
    }
    return StreamBuilder<List<HealthReport>>(
      stream: reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _messageState(
            icon: Icons.error_outline_rounded,
            message:
                'No se pudieron consultar los reportes. Inténtalo de nuevo.',
            action: TextButton.icon(
              onPressed: () =>
                  setState(() => _reports = _repository.watchReports()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar consulta'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _messageState(
            icon: Icons.hourglass_empty_rounded,
            message: 'Cargando reportes...',
          );
        }
        final items = snapshot.data ?? const <HealthReport>[];
        if (items.isEmpty) {
          return _messageState(
            icon: Icons.description_outlined,
            message: _canCreate
                ? 'Aún no hay reportes. Crea uno para comenzar.'
                : 'No hay reportes para mostrar.',
            action: _canCreate
                ? FilledButton.icon(
                    onPressed: _busy ? null : _openForm,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear reporte'),
                  )
                : null,
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 9),
          itemBuilder: (context, index) => _reportCard(items[index]),
        );
      },
    );
  }

  Widget _messageState({
    required IconData icon,
    required String message,
    Widget? action,
  }) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: BioMedicaColors.muted),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 10), action],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _reportCard(HealthReport report) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      border: Border.all(color: BioMedicaColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.build_circle_outlined,
            color: BioMedicaColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.id,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 11,
                ),
              ),
              if (_repository.role != AppRole.patient)
                Text(
                  'Paciente: ${_patientNames[report.ownerUid] ?? 'Paciente'}',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                report.otherMalestar?.isNotEmpty == true
                    ? '${report.malestar ?? report.equipment}: ${report.otherMalestar}'
                    : report.malestar ?? report.equipment,
                style: const TextStyle(
                  color: BioMedicaColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                report.description,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              _priorityChip(report.priority),
              Text(
                '${_formatDate(report.createdAt)}'
                '${report.pendingSync ? ' · pendiente de sincronizar' : ''}',
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 11,
                ),
              ),
              if (report.onsetAt != null)
                Text(
                  'Inicio: ${_formatDate(report.onsetAt!)}',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 11,
                  ),
                ),
              if (report.reviewStatus == 'reviewed') ...[
                const SizedBox(height: 7),
                const Text(
                  'Revisado por un médico',
                  style: TextStyle(
                    color: BioMedicaColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (report.reviewObservations?.isNotEmpty == true)
                  Text(
                    'Observaciones: ${report.reviewObservations}',
                    style: const TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 12,
                    ),
                  ),
              ] else
                const Text(
                  'Pendiente de revisión médica',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
                ),
              if (_repository.role == AppRole.doctor ||
                  _repository.role == AppRole.admin) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _startCall(report),
                    icon: const Icon(Icons.video_call_outlined),
                    label: const Text('Atender por llamada'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_repository.role == AppRole.patient)
          PopupMenuButton<String>(
            tooltip: 'Acciones del reporte',
            enabled: !_busy,
            onSelected: (action) {
              if (action == 'edit') _openForm(report);
              if (action == 'delete') _delete(report);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
      ],
    ),
  );

  Widget _priorityChip(String priority) {
    final color = switch (priority) {
      'Alta' => BioMedicaColors.red,
      'Media' => const Color(0xFF80530C),
      _ => BioMedicaColors.green,
    };
    return Container(
      margin: const EdgeInsets.only(top: 5, bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Prioridad: $priority',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}

class _ReportFormDialog extends StatefulWidget {
  const _ReportFormDialog({
    required this.report,
    required this.chronicConditions,
  });

  final HealthReport? report;
  final List<String> chronicConditions;

  @override
  State<_ReportFormDialog> createState() => _ReportFormDialogState();
}

class _ReportFormDialogState extends State<_ReportFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final String _draftId;
  late final _otherMalestar = TextEditingController(
    text: widget.report?.otherMalestar ?? '',
  );
  late final _description = TextEditingController(
    text: widget.report?.description ?? '',
  );
  late String _malestar =
      widget.report?.malestar ?? widget.report?.equipment ?? 'Fiebre';
  late String _priority = widget.report?.priority ?? 'Media';
  late DateTime _onsetAt = widget.report?.onsetAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _draftId = widget.report?.id ?? HealthReportDraft.generateId();
  }

  @override
  void dispose() {
    _otherMalestar.dispose();
    _description.dispose();
    super.dispose();
  }

  List<String> get _malestarOptions {
    final options = <String>{};
    for (final condition in widget.chronicConditions) {
      options.addAll(_conditionMalestares[condition] ?? const []);
    }
    if (options.isEmpty) options.addAll(HealthReportValidation.malestares);
    options.add('Otro');
    final current = widget.report?.malestar ?? widget.report?.equipment;
    if (current != null) options.add(current);
    return options.toList(growable: false);
  }

  static const _conditionMalestares = <String, List<String>>{
    'Hipertensión arterial': [
      'Dolor de cabeza',
      'Mareo',
      'Palpitaciones',
      'Hinchazón',
    ],
    'Diabetes tipo 2': [
      'Cansancio',
      'Cambios en la visión',
      'Mareo',
      'Náusea',
      'Hormigueo o entumecimiento',
    ],
    'Asma': ['Falta de aire', 'Tos', 'Opresión en el pecho'],
    'Enfermedad cardiovascular': [
      'Falta de aire',
      'Dolor en el pecho',
      'Palpitaciones',
      'Hinchazón',
      'Mareo',
    ],
    'Enfermedad renal crónica': [
      'Hinchazón',
      'Cansancio',
      'Náusea',
      'Cambios al orinar',
    ],
    'Enfermedad tiroidea': [
      'Cansancio',
      'Palpitaciones',
      'Mareo',
      'Cambios en la visión',
    ],
    'EPOC': ['Falta de aire', 'Tos', 'Opresión en el pecho'],
    'Artritis': ['Dolor articular', 'Hinchazón', 'Rigidez'],
    'Cáncer': ['Dolor', 'Fiebre', 'Náusea', 'Cansancio'],
    'Colesterol alto': [],
  };

  Future<void> _selectOnset() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _onsetAt,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_onsetAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _onsetAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    final onsetError = HealthReportValidation.onsetAt(_onsetAt);
    if (onsetError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(onsetError)));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      HealthReportDraft(
        id: _draftId,
        equipment: _malestar,
        description: _description.text.trim(),
        priority: _priority,
        malestar: _malestar,
        otherMalestar: _malestar == 'Otro' ? _otherMalestar.text.trim() : null,
        onsetAt: _onsetAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.report == null ? 'Nuevo reporte' : 'Editar reporte'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 390,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.report == null)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tag),
                  title: Text('ID automático'),
                  subtitle: Text('Se asignará al guardar el reporte.'),
                ),
              DropdownButtonFormField<String>(
                key: const ValueKey('reportMalestar'),
                initialValue: _malestarOptions.contains(_malestar)
                    ? _malestar
                    : _malestarOptions.first,
                decoration: const InputDecoration(labelText: 'Malestar *'),
                items: _malestarOptions
                    .map(
                      (malestar) => DropdownMenuItem(
                        value: malestar,
                        child: Text(malestar),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _malestar = value);
                },
              ),
              if (_malestar == 'Otro')
                TextFormField(
                  key: const ValueKey('reportOtherMalestar'),
                  controller: _otherMalestar,
                  decoration: const InputDecoration(
                    labelText: 'Especifica otro malestar *',
                  ),
                  maxLength: HealthReportValidation.maxMalestarLength,
                  validator: (value) =>
                      HealthReportValidation.otherMalestar(value, _malestar),
                ),
              TextFormField(
                key: const ValueKey('reportDescription'),
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descripción *'),
                maxLength: HealthReportValidation.maxDescriptionLength,
                maxLines: 3,
                validator: HealthReportValidation.description,
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('reportPriority'),
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Prioridad *'),
                items: HealthReportValidation.priorities
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority),
                      ),
                    )
                    .toList(),
                onChanged: (priority) {
                  if (priority != null) setState(() => _priority = priority);
                },
              ),
              ListTile(
                key: const ValueKey('reportOnsetAt'),
                contentPadding: EdgeInsets.zero,
                title: const Text('¿Desde cuándo comenzó? *'),
                subtitle: Text(_formatOnset(_onsetAt)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _selectOnset,
              ),
              const Text(
                'Si presentas dolor de pecho intenso, falta de aire grave o desmayo, busca atención de emergencia. Este reporte no sustituye una valoración médica.',
                style: TextStyle(fontSize: 12),
              ),
              const Text(
                'La prioridad refleja el impacto que percibes; no es una clasificación médica.',
                style: TextStyle(fontSize: 12),
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
        child: Text(widget.report == null ? 'Guardar' : 'Actualizar'),
      ),
    ],
  );

  String _formatOnset(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}
