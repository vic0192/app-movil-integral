import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/reminder_repository.dart';
import '../models/health_reminders.dart';
import '../services/local_reminder_scheduler.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key, this.repository, this.scheduler});

  final ReminderRepository? repository;
  final LocalReminderScheduler? scheduler;

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  late final ReminderRepository _repository =
      widget.repository ?? SupabaseReminderRepository();
  late final LocalReminderScheduler _scheduler =
      widget.scheduler ?? LocalReminderScheduler();
  List<MedicationReminder> _medications = const [];
  int _measurementIntervalHours = 24;
  TimeOfDay _measurementFirstTime = const TimeOfDay(hour: 9, minute: 0);
  bool _measurementEnabled = false;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final medications = await _repository.loadMedicationReminders();
      final settings = await _repository.loadMeasurementSettings();
      if (!mounted) return;
      setState(() {
        _medications = medications;
        if (settings != null) {
          _measurementIntervalHours = settings.intervalHours;
          _measurementFirstTime = settings.firstMeasurementTime;
          _measurementEnabled = settings.enabled;
        }
        _loading = false;
        _loadError = null;
      });
      await _scheduler.sync(
        medications: medications,
        measurementSettings: settings,
        requestPermission: false,
      );
    } on ReminderStoreException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'No se pudieron cargar los recordatorios: $error';
        });
      }
    }
  }

  Future<void> _editMedication([MedicationReminder? medication]) async {
    final draft = await showDialog<MedicationReminderDraft>(
      context: context,
      builder: (_) => _MedicationReminderDialog(medication: medication),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.saveMedicationReminder(draft);
      final notificationsGranted = await _syncNotifications(
        requestPermission: true,
      );
      if (mounted) {
        _showMessage(
          notificationsGranted
              ? 'Recordatorio de medicamento guardado.'
              : 'El recordatorio se guardó, pero debes permitir las '
                    'notificaciones en los ajustes del teléfono.',
        );
      }
    } on ReminderStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('No se pudo programar el recordatorio: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMedication(MedicationReminder medication) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar recordatorio'),
        content: Text(
          '¿Eliminar el recordatorio de ${medication.medicationName}?',
        ),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.deleteMedicationReminder(medication.id);
      await _syncNotifications(requestPermission: false);
      if (mounted) _showMessage('Recordatorio eliminado.');
    } on ReminderStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('No se pudo eliminar el recordatorio: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMeasurementSettings() async {
    final draft = MeasurementReminderDraft(
      intervalHours: _measurementIntervalHours,
      firstMeasurementTime: _measurementFirstTime,
      enabled: _measurementEnabled,
    );
    final error = draft.validate();
    if (error != null) {
      _showMessage(error);
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.saveMeasurementSettings(draft);
      final notificationsGranted = await _syncNotifications(
        requestPermission: true,
      );
      if (mounted) {
        _showMessage(
          notificationsGranted
              ? 'Recordatorio de medición guardado.'
              : 'El recordatorio se guardó, pero debes permitir las '
                    'notificaciones en los ajustes del teléfono.',
        );
      }
    } on ReminderStoreException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('No se pudo programar el recordatorio: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _syncNotifications({required bool requestPermission}) async {
    final medications = await _repository.loadMedicationReminders();
    final settings = await _repository.loadMeasurementSettings();
    if (!mounted) return false;
    setState(() {
      _medications = medications;
    });
    final granted = await _scheduler.sync(
      medications: medications,
      measurementSettings: settings,
      requestPermission: requestPermission,
    );
    return granted;
  }

  Future<void> _pickMeasurementTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _measurementFirstTime,
      helpText: 'Primera hora para medir',
    );
    if (selected != null && mounted) {
      setState(() => _measurementFirstTime = selected);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recordatorios de salud')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          )
        : SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _sectionTitle(
                  'Medicamentos',
                  'Los avisos se repiten según la frecuencia seleccionada.',
                  action: IconButton(
                    tooltip: 'Agregar medicamento',
                    onPressed: _busy ? null : () => _editMedication(),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ),
                if (_medications.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Aún no tienes recordatorios de medicamentos.',
                      ),
                    ),
                  )
                else
                  ..._medications.map(_medicationCard),
                const SizedBox(height: 24),
                _sectionTitle(
                  'Medición de signos vitales',
                  'El teléfono te avisará cuándo registrar una nueva medición.',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Activar recordatorio'),
                          value: _measurementEnabled,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _measurementEnabled = value),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _measurementIntervalHours,
                          decoration: const InputDecoration(
                            labelText: 'Frecuencia',
                          ),
                          items: _intervalOptions
                              .map(
                                (hours) => DropdownMenuItem(
                                  value: hours,
                                  child: Text(_frequencyLabel(hours)),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(
                                      () => _measurementIntervalHours = value,
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickMeasurementTime,
                          icon: const Icon(Icons.access_time_rounded),
                          label: Text(
                            'Primera medición: '
                            '${_measurementFirstTime.format(context)}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy ? null : _saveMeasurementSettings,
                          child: const Text('Guardar recordatorio de medición'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Los avisos son locales a este teléfono y pueden retrasarse '
                  'por las restricciones de ahorro de batería. No sustituyen '
                  'las indicaciones de un profesional de salud.',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
  );

  Widget _sectionTitle(String title, String subtitle, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      );

  Widget _medicationCard(MedicationReminder medication) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.medication_outlined)),
      title: Text(medication.medicationName),
      subtitle: Text(
        '${medication.dose?.isNotEmpty == true ? '${medication.dose} · ' : ''}'
        '${_frequencyLabel(medication.intervalHours)} · '
        '${medication.firstDoseTime.format(context)}',
      ),
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        onSelected: (action) {
          if (action == 'edit') _editMedication(medication);
          if (action == 'delete') _deleteMedication(medication);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Editar')),
          PopupMenuItem(value: 'delete', child: Text('Eliminar')),
        ],
      ),
    ),
  );
}

const _intervalOptions = [4, 6, 8, 12, 24];

String _frequencyLabel(int hours) =>
    hours == 24 ? 'Cada día' : 'Cada $hours horas';

class _MedicationReminderDialog extends StatefulWidget {
  const _MedicationReminderDialog({this.medication});

  final MedicationReminder? medication;

  @override
  State<_MedicationReminderDialog> createState() =>
      _MedicationReminderDialogState();
}

class _MedicationReminderDialogState extends State<_MedicationReminderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dose;
  late int _intervalHours;
  late TimeOfDay _firstDoseTime;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    _name = TextEditingController(text: medication?.medicationName ?? '');
    _dose = TextEditingController(text: medication?.dose ?? '');
    _intervalHours = medication?.intervalHours ?? 24;
    _firstDoseTime =
        medication?.firstDoseTime ?? const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _firstDoseTime,
      helpText: 'Primera toma',
    );
    if (selected != null && mounted) {
      setState(() => _firstDoseTime = selected);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MedicationReminderDraft(
        id: widget.medication?.id,
        medicationName: _name.text.trim(),
        dose: _dose.text.trim(),
        intervalHours: _intervalHours,
        firstDoseTime: _firstDoseTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.medication == null ? 'Nuevo medicamento' : 'Editar medicamento',
    ),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Medicamento',
                counterText: '',
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Escribe el nombre del medicamento.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dose,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Dosis (opcional)',
                hintText: 'Ej. 1 tableta',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _intervalHours,
              decoration: const InputDecoration(labelText: 'Cada cuándo'),
              items: _intervalOptions
                  .map(
                    (hours) => DropdownMenuItem(
                      value: hours,
                      child: Text(_frequencyLabel(hours)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _intervalHours = value);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time_rounded),
              label: Text('Primera toma: ${_firstDoseTime.format(context)}'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}
