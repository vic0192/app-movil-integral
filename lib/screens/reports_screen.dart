import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bio_medica_colors.dart';
import '../data/firestore_report_repository.dart';
import '../models/health_report.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.patientName, this.repository});

  final String patientName;
  final ReportRepository? repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportRepository _repository =
      widget.repository ?? FirestoreReportRepository();
  final _search = TextEditingController();
  Stream<List<HealthReport>>? _reports;
  String? _initializationError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _repository.initialize();
      if (mounted) setState(() => _reports = _repository.watchReports());
    } on ReportStoreException catch (error) {
      if (mounted) setState(() => _initializationError = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _initializationError =
              'No se pudo iniciar Firestore. Comprueba la configuración '
              'de Firebase. Detalle: $error',
        );
      }
    }
  }

  Future<void> _openForm([HealthReport? report]) async {
    final draft = await showDialog<HealthReportDraft>(
      context: context,
      builder: (_) => _ReportFormDialog(report: report),
    );
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (report == null) {
        final id = await _repository.createReport(
          draft,
          documentId: draft.id.isEmpty ? null : draft.id,
        );
        if (mounted) {
          _showMessage('Reporte $id guardado; sincronización en curso.');
        }
      } else {
        await _repository.updateReport(report.id, draft);
        if (mounted) _showMessage('Reporte actualizado.');
      }
    } on ReportStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('No se pudo guardar el reporte: $error');
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
      if (mounted) _showMessage('No se pudo eliminar el reporte: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyOwnerUid() async {
    final ownerUid = _repository.ownerUid;
    if (ownerUid == null) return;
    await Clipboard.setData(ClipboardData(text: ownerUid));
    if (mounted) _showMessage('UID de Firebase copiado.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                    'Reportes de equipo',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    widget.patientName,
                    style: const TextStyle(color: BioMedicaColors.muted),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              key: const ValueKey('newReport'),
              tooltip: 'Nuevo reporte',
              onPressed: _busy ? null : _openForm,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: _ownerCard(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
          key: const ValueKey('searchReport'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Buscar por ID (por ejemplo, REP001)',
            suffixIcon: IconButton(
              tooltip: 'Limpiar búsqueda',
              onPressed: () {
                _search.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      Expanded(child: _reportList()),
    ],
  );

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
              const Text(
                'Reportes privados del usuario autenticado.',
                style: TextStyle(fontSize: 12),
              ),
              if (_repository.ownerUid case final uid?)
                SelectableText(
                  'UID para pruebas: $uid',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        if (_repository.ownerUid != null)
          IconButton(
            tooltip: 'Copiar UID',
            visualDensity: VisualDensity.compact,
            onPressed: _copyOwnerUid,
            icon: const Icon(Icons.copy_rounded, size: 16),
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
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<HealthReport>>(
      stream: reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _messageState(
            icon: Icons.error_outline_rounded,
            message: 'No se pudieron consultar los reportes: ${snapshot.error}',
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
          return const Center(child: CircularProgressIndicator());
        }
        final query = _search.text.trim().toLowerCase();
        final items = (snapshot.data ?? const <HealthReport>[])
            .where((report) => report.id.toLowerCase().contains(query))
            .toList();
        if (items.isEmpty) {
          return _messageState(
            icon: Icons.description_outlined,
            message: query.isEmpty
                ? 'Aún no hay reportes. Crea uno para comenzar.'
                : 'No se encontró el reporte "$query".',
            action: query.isEmpty
                ? FilledButton.icon(
                    onPressed: _busy ? null : _openForm,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear reporte'),
                  )
                : null,
          );
        }
        return ListView.separated(
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
  }) => Center(
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
            style: const TextStyle(color: BioMedicaColors.muted, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
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
              Text(
                report.equipment,
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
            ],
          ),
        ),
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
  const _ReportFormDialog({required this.report});

  final HealthReport? report;

  @override
  State<_ReportFormDialog> createState() => _ReportFormDialogState();
}

class _ReportFormDialogState extends State<_ReportFormDialog> {
  static const _priorities = ['Baja', 'Media', 'Alta'];

  final _formKey = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.report?.id ?? '');
  late final _equipment = TextEditingController(
    text: widget.report?.equipment ?? '',
  );
  late final _description = TextEditingController(
    text: widget.report?.description ?? '',
  );
  late String _priority = widget.report?.priority ?? 'Media';

  @override
  void dispose() {
    _id.dispose();
    _equipment.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      HealthReportDraft(
        id: _id.text.trim(),
        equipment: _equipment.text.trim(),
        description: _description.text.trim(),
        priority: _priority,
      ),
    );
  }

  String? _requiredValidator(String? value, String label, int maximum) {
    if (value?.trim().isEmpty ?? true) return 'Escribe $label.';
    if (value!.trim().length > maximum) return 'Máximo $maximum caracteres.';
    return null;
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
                TextFormField(
                  key: const ValueKey('reportId'),
                  controller: _id,
                  decoration: const InputDecoration(
                    labelText: 'ID (opcional, por ejemplo REP001)',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[/\s]')),
                  ],
                  validator: (value) {
                    if (value?.contains('/') ?? false) {
                      return 'El ID no puede contener /.';
                    }
                    return null;
                  },
                ),
              TextFormField(
                key: const ValueKey('reportEquipment'),
                controller: _equipment,
                decoration: const InputDecoration(labelText: 'Equipo *'),
                maxLength: 100,
                validator: (value) =>
                    _requiredValidator(value, 'el equipo', 100),
              ),
              TextFormField(
                key: const ValueKey('reportDescription'),
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descripción *'),
                maxLength: 500,
                maxLines: 3,
                validator: (value) =>
                    _requiredValidator(value, 'la descripción', 500),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('reportPriority'),
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Prioridad *'),
                items: _priorities
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
}
