import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:health/health.dart';

import '../bio_medica_colors.dart';
import '../data/health_connect_repository.dart';
import '../models/health_connect_record.dart';
import '../services/health_connect_service.dart';

class HealthConnectScreen extends StatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  final HealthConnectService _healthService = HealthConnectService();
  final HealthConnectRepository _repository = HealthConnectRepository();
  List<HealthConnectRecord> _records = [];
  HealthConnectSdkStatus? _status;
  bool _loading = true;
  bool _syncing = false;
  bool _statusLoading = true;
  String? _loadError;
  String? _statusError;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadRecords();
  }

  Future<void> _loadStatus() async {
    if (!_isAndroid) {
      setState(() {
        _statusLoading = false;
        _statusError =
            'Health Connect se puede sincronizar desde un teléfono Android.';
      });
      return;
    }
    try {
      final status = await _healthService.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusLoading = false;
        if (status == null) {
          _statusError = 'No se pudo comprobar el estado de Health Connect.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusLoading = false;
        _statusError = 'No se pudo comprobar Health Connect. Inténtalo de nuevo.';
      });
    }
  }

  Future<void> _loadRecords() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _repository.initialize();
      final records = await _repository.loadRecentRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudieron cargar los datos guardados. Inténtalo de nuevo.';
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _message = null;
      _loadError = null;
    });
    try {
      final result = await _healthService.readRecentData();
      if (result.records.isNotEmpty) {
        await _repository.saveRecords(result.records);
      }
      final records = await _repository.loadRecentRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _message = switch (result.authorizedTypes) {
          0 =>
            'No se concedieron permisos de lectura. Puedes elegirlos en '
                'los permisos de Health Connect y volver a intentar.',
          _ when result.records.isEmpty =>
            'Permisos activos, pero no hay lecturas de los últimos 7 días. '
                'Verifica que Samsung Health comparta esos datos con Health Connect.',
          _ =>
            'Se revisaron ${result.records.length} lecturas de '
                '${result.authorizedTypes} tipos en los últimos 7 días.',
        };
        _syncing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudo sincronizar. Inténtalo de nuevo.';
        _syncing = false;
      });
    }
  }

  Future<void> _installHealthConnect() async {
    try {
      await _healthService.installOrUpdateHealthConnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si no se abrió Play Store, instala o actualiza Health Connect '
            'manualmente y vuelve a comprobar.',
          ),
        ),
      );
      await _loadStatus();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _statusError = 'No se pudo abrir la instalación. Inténtalo de nuevo.',
      );
    }
  }

  Future<void> _openSharingSettings() async {
    try {
      await _healthService.openSettings();
    } catch (error) {
      if (mounted) {
        setState(
          () =>           _statusError =
              'No se pudo abrir la configuración de Health Connect. Inténtalo de nuevo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BioMedicaColors.canvas,
      appBar: AppBar(
        title: const Text('Datos médicos sincronizados'),
        backgroundColor: BioMedicaColors.surface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _consentCard(),
            const SizedBox(height: 12),
            _healthConnectStatus(),
            if (_isAndroid && _status != HealthConnectSdkStatus.sdkAvailable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _statusLoading ? null : _installHealthConnect,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Instalar o actualizar Health Connect'),
                ),
              ),
            if (_isAndroid) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('openHealthConnectSettings'),
                onPressed: _openSharingSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Configurar intercambio de datos'),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed:
                  _status == HealthConnectSdkStatus.sdkAvailable &&
                      !_syncing &&
                      !_statusLoading
                  ? _sync
                  : null,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_syncing ? 'Sincronizando…' : 'Sincronizar ahora'),
            ),
            if (_statusError != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusError!,
                style: const TextStyle(color: BioMedicaColors.red),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              _messageCard(_message!),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _loadError!,
                style: const TextStyle(color: BioMedicaColors.red),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Lecturas más recientes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ..._categoryCards(),
            const SizedBox(height: 14),
            _ecgNotice(),
            const SizedBox(height: 12),
            const Text(
              'La presión arterial aparece solo cuando una fuente autorizada '
              'la comparte con Health Connect. ECG y forma de onda no se '
              'simulan ni se leen desde permisos protegidos de Samsung.',
              style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consentCard() => Card(
    color: BioMedicaColors.surface,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'La primera vez, toca “Sincronizar ahora” para conceder permisos de '
        'lectura a Health Connect. Después BioMedica importará automáticamente '
        'las lecturas autorizadas al abrir o volver a la app, si Samsung Health '
        'las comparte. También puedes sincronizar manualmente. Se guardan en tu '
        'cuenta los datos de los últimos 7 días con fuente y fecha; BioMedica '
        'no escribe datos en Health Connect. Usa “Configurar intercambio de '
        'datos” para habilitar Samsung Health como origen.',
      ),
    ),
  );

  Widget _healthConnectStatus() {
    final statusText = _statusLoading
        ? 'Comprobando Health Connect…'
        : !_isAndroid
        ? 'La sincronización está disponible en Android.'
        : _status == HealthConnectSdkStatus.sdkAvailable
        ? 'Health Connect está disponible.'
        : _status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired
        ? 'Health Connect necesita instalarse o actualizarse.'
        : 'Health Connect no está disponible en este dispositivo.';
    return Card(
      color: BioMedicaColors.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.health_and_safety_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(statusText)),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(String message) => Card(
    color: BioMedicaColors.primaryLight,
    child: Padding(padding: const EdgeInsets.all(14), child: Text(message)),
  );

  List<Widget> _categoryCards() {
    const categories = <({String title, List<String> types})>[
      (
        title: 'Frecuencia cardiaca',
        types: ['HEART_RATE', 'RESTING_HEART_RATE'],
      ),
      (title: 'Oxígeno en sangre (SpO₂)', types: ['BLOOD_OXYGEN']),
      (
        title: 'Presión arterial',
        types: ['BLOOD_PRESSURE_SYSTOLIC', 'BLOOD_PRESSURE_DIASTOLIC'],
      ),
      (
        title: 'Composición corporal',
        types: [
          'BODY_FAT_PERCENTAGE',
          'LEAN_BODY_MASS',
          'BODY_MASS_INDEX',
          'BODY_WATER_MASS',
          'WEIGHT',
          'HEIGHT',
        ],
      ),
      (
        title: 'Sueño',
        types: [
          'SLEEP_SESSION',
          'SLEEP_ASLEEP',
          'SLEEP_DEEP',
          'SLEEP_LIGHT',
          'SLEEP_REM',
        ],
      ),
    ];
    return categories
        .map((category) {
          final matches = _records
              .where((record) => category.types.contains(record.dataType))
              .take(5)
              .toList(growable: false);
          return Card(
            color: BioMedicaColors.surface,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (matches.isEmpty)
                    const Text(
                      'Sin datos compartidos desde Health Connect.',
                      style: TextStyle(color: BioMedicaColors.muted),
                    )
                  else
                    ...matches.map(_recordTile),
                ],
              ),
            ),
          );
        })
        .toList(growable: false);
  }

  Widget _recordTile(HealthConnectRecord record) {
    final date = record.recordedAt.toLocal();
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final source = record.sourceName.isEmpty
        ? 'Fuente no identificada'
        : record.sourceName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.label),
                Text(
                  '$dateText · $source',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.displayValue,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _ecgNotice() => Card(
    color: BioMedicaColors.surface,
    child: const ListTile(
      leading: Icon(Icons.monitor_heart_outlined),
      title: Text('ECG y forma de onda'),
      subtitle: Text(
        'No disponibles mediante Health Connect en este Android. '
        'Se requiere una integración oficial autorizada de Samsung.',
      ),
    ),
  );

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
