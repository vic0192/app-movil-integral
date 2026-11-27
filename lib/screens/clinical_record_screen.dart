import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/api_report_repository.dart';
import '../data/clinical_video_call_repository.dart';
import '../data/clinical_record_repository.dart';
import '../data/health_connect_repository.dart';
import '../data/supabase_measurement_repository.dart';
import '../models/app_user_profile.dart';
import '../models/clinical_record_entry.dart';
import '../models/health_connect_record.dart';
import '../models/health_report.dart';
import '../models/wearable_measurement.dart';
import '../widgets/clinical_call_invite_dialog.dart';

class ClinicalRecordScreen extends StatefulWidget {
  const ClinicalRecordScreen({
    super.key,
    required this.canEdit,
    this.canCall = false,
    this.initialPatientUid,
    this.callRepository,
  });

  final bool canEdit;
  final bool canCall;
  final String? initialPatientUid;
  final ClinicalVideoCallRepository? callRepository;

  @override
  State<ClinicalRecordScreen> createState() => _ClinicalRecordScreenState();
}

class _ClinicalRecordScreenState extends State<ClinicalRecordScreen> {
  final _recordRepository = ClinicalRecordRepository();
  final _measurementRepository = SupabaseMeasurementRepository();
  final _healthConnectRepository = HealthConnectRepository();
  final _reportRepository = ApiReportRepository();
  late final ClinicalVideoCallRepository _callRepository =
      widget.callRepository ?? SupabaseClinicalVideoCallRepository();
  List<AppUserProfile> _patients = const [];
  String? _selectedPatientUid;
  Stream<List<WearableMeasurement>>? _measurements;
  Stream<List<SharedHealthConnectRecord>>? _healthRecords;
  Stream<List<HealthReport>>? _reports;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _recordRepository.initialize();
      final patients = await _recordRepository.loadPatients();
      await _measurementRepository.initialize();
      if (!kIsWeb) await _healthConnectRepository.initialize();
      await _reportRepository.initialize();
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _selectedPatientUid = _initialPatient(patients);
        _measurements = _measurementRepository.watchMeasurements();
        _healthRecords = kIsWeb
            ? Stream.value(const <SharedHealthConnectRecord>[])
            : _healthConnectRepository.watchRecordsForClinicians();
        _reports = _reportRepository.watchReports();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el expediente. Inténtalo de nuevo.';
        _loading = false;
      });
    }
  }

  String? _initialPatient(List<AppUserProfile> patients) {
    final requestedUid = widget.initialPatientUid;
    if (requestedUid != null &&
        patients.any((patient) => patient.uid == requestedUid)) {
      return requestedUid;
    }
    return patients.isEmpty ? null : patients.first.uid;
  }

  AppUserProfile? get _selectedPatient {
    for (final patient in _patients) {
      if (patient.uid == _selectedPatientUid) return patient;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error case final error?) {
      return _stateMessage(error);
    }
    if (_patients.isEmpty) {
      return _stateMessage('No hay pacientes autorizados para este acceso.');
    }

    final patient = _selectedPatient;
    if (patient == null) {
      return _stateMessage('Selecciona un paciente asignado.');
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: patient.uid,
                  decoration: const InputDecoration(
                    labelText: 'Expediente del paciente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _patients
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.uid,
                          child: Text(
                            item.displayName.isEmpty
                                ? 'Paciente ${item.uid.substring(0, 8)}'
                                : item.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (uid) {
                    if (uid != null) setState(() => _selectedPatientUid = uid);
                  },
                ),
                const SizedBox(height: 8),
                _patientBackground(patient),
                if (widget.canCall)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _startPatientCall(patient),
                      icon: const Icon(Icons.video_call_outlined),
                      label: const Text('Atender por llamada'),
                    ),
                  ),
                const SizedBox(height: 8),
                const TabBar(
                  tabs: [
                    Tab(text: 'Clínico'),
                    Tab(text: 'Mediciones'),
                    Tab(text: 'Reportes'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _clinicalEntries(patient),
                _measurementTimeline(patient.uid),
                _reportTimeline(patient.uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientBackground(AppUserProfile patient) {
    final conditions = [
      ...patient.chronicConditions,
      if (patient.otherChronicCondition case final other? when other.isNotEmpty)
        other,
    ];
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: BioMedicaColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.assignment_ind_outlined,
            color: BioMedicaColors.primary,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              conditions.isEmpty
                  ? 'Sin padecimientos crónicos registrados en el perfil.'
                  : 'Antecedentes: ${conditions.join(', ')}',
              style: const TextStyle(
                color: BioMedicaColors.ink,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clinicalEntries(AppUserProfile patient) => Column(
    children: [
      if (widget.canEdit)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _addEntry(patient),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar entrada'),
            ),
          ),
        ),
      Expanded(
        child: StreamBuilder<List<ClinicalRecordEntry>>(
          key: ValueKey('clinical-${patient.uid}'),
          stream: _recordRepository.watchEntries(patient.uid),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _stateMessage(
                'No se pudo leer el expediente. Inténtalo de nuevo.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return _stateMessage(
                'Aún no hay diagnósticos, notas, medicamentos, alergias o '
                'consultas registrados.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _entryCard(entries[index]),
            );
          },
        ),
      ),
    ],
  );

  Widget _measurementTimeline(String patientUid) => StreamBuilder<
    List<WearableMeasurement>
  >(
    stream: _measurements,
    builder: (context, measurementSnapshot) {
      if (measurementSnapshot.hasError) {
        return _stateMessage(
          'No se pudieron leer las mediciones. Inténtalo de nuevo.',
        );
      }
      if (!measurementSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final measurements = measurementSnapshot.data!
          .where((item) => item.ownerUid == patientUid)
          .toList(growable: false);
      return StreamBuilder<List<SharedHealthConnectRecord>>(
        stream: _healthRecords,
        builder: (context, healthSnapshot) {
          if (healthSnapshot.hasError) {
            return _stateMessage(
              'No se pudieron leer los datos sincronizados. Inténtalo de nuevo.',
            );
          }
          if (!healthSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final healthRecords = healthSnapshot.data!
              .where((item) => item.patientUid == patientUid)
              .toList(growable: false);
          if (measurements.isEmpty && healthRecords.isEmpty) {
            return _stateMessage(
              'No hay mediciones del reloj ni registros de Health Connect.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final item in measurements) _wearMeasurementCard(item),
              for (final item in healthRecords) _healthRecordCard(item),
            ],
          );
        },
      );
    },
  );

  Widget _reportTimeline(String patientUid) => StreamBuilder<List<HealthReport>>(
    stream: _reports,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _stateMessage(
          'No se pudieron leer los reportes. Inténtalo de nuevo.',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final reports = snapshot.data!
          .where((item) => item.ownerUid == patientUid)
          .toList(growable: false);
      if (reports.isEmpty) {
        return _stateMessage('Este paciente todavía no tiene reportes.');
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _reportCard(reports[index]),
      );
    },
  );

  Widget _entryCard(ClinicalRecordEntry entry) {
    final color = switch (entry.type) {
      ClinicalEntryType.diagnosis => const Color(0xFF1976D2),
      ClinicalEntryType.clinicalNote => const Color(0xFF546E7A),
      ClinicalEntryType.medication => const Color(0xFF168A83),
      ClinicalEntryType.allergy => BioMedicaColors.red,
      ClinicalEntryType.visit => const Color(0xFF7755A5),
    };
    return Card(
      color: BioMedicaColors.surface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color.lerp(color, Colors.white, 0.86),
          child: Icon(_entryIcon(entry.type), color: color, size: 20),
        ),
        title: Text(entry.title),
        subtitle: Text(
          '${_formatDate(entry.occurredAt)} · ${entry.type.label}\n'
          '${entry.details}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _wearMeasurementCard(WearableMeasurement measurement) => Card(
    color: BioMedicaColors.surface,
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: BioMedicaColors.primaryLight,
        child: Icon(Icons.favorite_rounded, color: BioMedicaColors.primary),
      ),
      title: Text('${measurement.heartRateBpm} BPM · ${_formatDate(measurement.readingAt)}'),
      subtitle: Text(
        'Galaxy Watch · ${measurement.deviceName}'
        '${measurement.oxygenSaturationPercent == null ? '' : '\nSpO₂: ${measurement.oxygenSaturationPercent}%'}'
        '${measurement.bodyTemperatureCelsius == null ? '' : '\nTemperatura: ${measurement.bodyTemperatureCelsius!.toStringAsFixed(1)} °C'}',
      ),
    ),
  );

  Widget _healthRecordCard(SharedHealthConnectRecord item) => Card(
    color: BioMedicaColors.surface,
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: BioMedicaColors.primaryLight,
        child: Icon(
          _healthIcon(item.record.dataType),
          color: BioMedicaColors.primary,
        ),
      ),
      title: Text('${item.record.label} · ${item.record.displayValue}'),
      subtitle: Text(
        '${item.patientName.isEmpty ? 'Paciente ${item.patientUid.substring(0, 8)}' : item.patientName}'
        ' · ${item.record.sourceName.isEmpty ? 'Health Connect' : item.record.sourceName}'
        '\n${_formatDate(item.record.recordedAt)}',
      ),
    ),
  );

  Widget _reportCard(HealthReport report) => Card(
    color: BioMedicaColors.surface,
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: BioMedicaColors.primaryLight,
        child: Icon(Icons.assignment_outlined, color: BioMedicaColors.primary),
      ),
      title: Text(report.malestar ?? report.equipment),
      subtitle: Text(
        '${report.priority} · ${report.reviewStatus == 'reviewed' ? 'Revisado' : 'Pendiente'}'
        '\n${_formatDate(report.createdAt)} · ${report.description}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  Future<void> _addEntry(AppUserProfile patient) async {
    final draft = await showDialog<ClinicalRecordDraft>(
      context: context,
      builder: (context) => _ClinicalEntryDialog(patientUid: patient.uid),
    );
    if (draft == null || !mounted) return;
    try {
      await _recordRepository.addEntry(draft);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar en el expediente. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  Future<void> _startPatientCall(AppUserProfile patient) async {
    try {
      final call = await _callRepository.createCall(patient.uid);
      if (!mounted) return;
      await showClinicalCallInviteDialog(context, call);
    } on ClinicalVideoCallException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo iniciar la videollamada. Inténtalo de nuevo.'),
          ),
        );
      }
    }
  }

  Widget _stateMessage(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: BioMedicaColors.muted),
      ),
    ),
  );

  static IconData _entryIcon(ClinicalEntryType type) => switch (type) {
    ClinicalEntryType.diagnosis => Icons.medical_information_outlined,
    ClinicalEntryType.clinicalNote => Icons.description_outlined,
    ClinicalEntryType.medication => Icons.medication_outlined,
    ClinicalEntryType.allergy => Icons.warning_amber_rounded,
    ClinicalEntryType.visit => Icons.event_note_outlined,
  };

  static IconData _healthIcon(String type) => switch (type) {
    'HEART_RATE' || 'RESTING_HEART_RATE' => Icons.favorite_rounded,
    'BLOOD_OXYGEN' => Icons.air_rounded,
    'BODY_TEMPERATURE' => Icons.thermostat_rounded,
    'BLOOD_PRESSURE_SYSTOLIC' || 'BLOOD_PRESSURE_DIASTOLIC' =>
      Icons.bloodtype_rounded,
    _ => Icons.health_and_safety_outlined,
  };

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ClinicalEntryDialog extends StatefulWidget {
  const _ClinicalEntryDialog({required this.patientUid});

  final String patientUid;

  @override
  State<_ClinicalEntryDialog> createState() => _ClinicalEntryDialogState();
}

class _ClinicalEntryDialogState extends State<_ClinicalEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  ClinicalEntryType _type = ClinicalEntryType.clinicalNote;

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agregar al expediente'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ClinicalEntryType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo de entrada'),
              items: ClinicalEntryType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (type) {
                if (type != null) setState(() => _type = type);
              },
            ),
            TextFormField(
              controller: _titleController,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Título'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe un título.'
                  : null,
            ),
            TextFormField(
              controller: _detailsController,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Detalles / indicaciones',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe los detalles.'
                  : null,
            ),
            const Text(
              'La entrada se añadirá con fecha y autor. El expediente conserva '
              'las entradas como historial y no permite borrarlas desde la app.',
              style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
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
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            ClinicalRecordDraft(
              patientUid: widget.patientUid,
              type: _type,
              title: _titleController.text,
              details: _detailsController.text,
              occurredAt: DateTime.now(),
            ),
          );
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}
