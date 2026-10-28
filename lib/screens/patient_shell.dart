import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bio_medica_colors.dart';
import '../ble/wearable_bluetooth_service.dart';
import '../ble/wear_os_data_layer.dart';
import '../data/biomedica_api.dart';
import '../data/reminder_repository.dart';
import '../data/supabase_measurement_repository.dart';
import '../models/wearable_measurement.dart';
import '../services/health_home_widget.dart';
import '../services/local_reminder_scheduler.dart';
import '../widgets/history_reading_tile.dart';
import '../widgets/turn_queue_demo.dart';
import '../widgets/turn_status_hero.dart';
import '../widgets/vital_indicator_card.dart';
import 'reports_screen.dart';
import 'reminder_settings_screen.dart';
import 'wearable_pairing_sheet.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({
    super.key,
    required this.patientName,
    required this.patientEmail,
    this.chronicConditions = const [],
    required this.onSignOut,
    this.isDemo = false,
    this.measurementRepository,
  });

  final String patientName;
  final String patientEmail;
  final List<String> chronicConditions;
  final VoidCallback onSignOut;
  final bool isDemo;
  final MeasurementRepository? measurementRepository;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  final _api = const BioMedicaApi();
  final _wearableBluetooth = WearableBluetoothService();
  late final MeasurementRepository _measurementRepository =
      widget.measurementRepository ?? SupabaseMeasurementRepository();
  final _reminderRepository = SupabaseReminderRepository();
  final _reminderScheduler = LocalReminderScheduler();
  final _demoRates = const [72, 75, 71, 78, 76, 73, 77, 74];
  final _demoOxygenSaturation = const [98, 97, 99, 98, 96, 98, 97, 99];
  final _demoTemperatures = const [
    36.6,
    36.5,
    36.7,
    36.6,
    36.8,
    36.5,
    36.6,
    36.7,
  ];
  Timer? _timer;
  Timer? _demoTelemetryTimer;
  Timer? _watchFreshnessTimer;
  StreamSubscription<Map<String, dynamic>>? _watchSubscription;
  StreamSubscription<List<WearableMeasurement>>? _measurementSubscription;
  int _tab = 0;
  int _demoReadingIndex = 0;
  bool _apiAvailable = false;
  bool _demoWearableLinked = false;
  int? _watchHeartRate;
  int? _watchOxygenSaturation;
  double? _watchTemperature;
  String? _watchSource;
  String? _watchDeviceName;
  DateTime? _watchUpdatedAt;
  DateTime? _wearableUpdatedAt;
  List<WearableMeasurement> _savedMeasurements = const [];
  String? _measurementError;
  bool _savingMeasurement = false;
  Map<String, dynamic> _telemetry = const {};
  List<Map<String, dynamic>> _history = const [];

  @override
  void initState() {
    super.initState();
    _wearableBluetooth.addListener(_onWearableChanged);
    _watchSubscription = WearOsDataLayer.readings.listen(
      _onWatchReading,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('No se pudieron recibir datos de BioWatch: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    unawaited(_loadLatestWatchReading());
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _watchFreshnessTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshWatchFreshness(),
    );
    unawaited(_initializeMeasurements());
    if (!widget.isDemo) unawaited(_restoreReminders());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _demoTelemetryTimer?.cancel();
    _watchFreshnessTimer?.cancel();
    unawaited(_watchSubscription?.cancel());
    unawaited(_measurementSubscription?.cancel());
    _wearableBluetooth.removeListener(_onWearableChanged);
    _wearableBluetooth.dispose();
    super.dispose();
  }

  void _onWearableChanged() {
    if (_wearableBluetooth.heartRate != null) {
      _wearableUpdatedAt = DateTime.now();
    }
    if (mounted) setState(() {});
    unawaited(_updateHomeWidget());
  }

  Future<void> _refresh() async {
    try {
      final status = await _api.fetchStatus();
      final telemetry = status['lastTelemetry'];
      final history = status['telemetryHistory'];
      if (!mounted) return;
      setState(() {
        _apiAvailable = true;
        _telemetry = telemetry is Map<String, dynamic> ? telemetry : const {};
        _history = history is List
            ? history
                  .whereType<Map>()
                  .map((point) => Map<String, dynamic>.from(point))
                  .toList()
            : const [];
      });
      await _updateHomeWidget();
    } catch (_) {
      if (mounted) {
        setState(() => _apiAvailable = false);
        await _updateHomeWidget();
      }
    }
  }

  bool get _hasRealData =>
      _wearableBluetooth.heartRate != null ||
      _wearableBluetooth.oxygenSaturation != null ||
      _wearableBluetooth.temperature != null ||
      (_watchIsConnected && _watchHeartRate != null) ||
      (_apiAvailable &&
          !_isDemoTelemetry &&
          (_value('heartRate') > 0 ||
              _value('spo2') > 0 ||
              _decimal('temperature') > 0));

  bool get _canSaveMeasurement =>
      !widget.isDemo &&
      !_savingMeasurement &&
      (_wearableBluetooth.isConnected &&
              _wearableBluetooth.heartRate != null &&
              _isRecent(_wearableUpdatedAt) ||
          _watchIsConnected &&
              _watchSource == 'wear_os_sensor' &&
              _watchHeartRate != null);

  bool _isRecent(DateTime? timestamp) {
    if (timestamp == null) return false;
    final age = DateTime.now().difference(timestamp);
    return !age.isNegative && age <= const Duration(minutes: 5);
  }

  bool get _watchIsConnected =>
      _watchUpdatedAt != null &&
      DateTime.now().difference(_watchUpdatedAt!) < const Duration(seconds: 10);

  bool get _isDemoTelemetry {
    final source = '${_telemetry['source'] ?? ''}'.toLowerCase();
    return source.isEmpty ||
        source.contains('demo') ||
        source.contains('emulator') ||
        source == 'cloud-idle';
  }

  int get _currentHeartRate =>
      _wearableBluetooth.heartRate ??
      (_watchIsConnected && _watchHeartRate != null
          ? _watchHeartRate!
          : _demoWearableLinked
          ? _demoRates[_demoReadingIndex]
          : (_value('heartRate') > 0 ? _value('heartRate') : 74));

  int get _currentSpo2 =>
      _wearableBluetooth.oxygenSaturation?.round() ??
      (_watchIsConnected && _watchOxygenSaturation != null
          ? _watchOxygenSaturation!
          : _demoWearableLinked
          ? _demoOxygenSaturation[_demoReadingIndex]
          : (_value('spo2') > 0 ? _value('spo2') : 98));

  double get _currentTemperature =>
      _wearableBluetooth.temperature ??
      (_watchIsConnected && _watchTemperature != null
          ? _watchTemperature!
          : _demoWearableLinked
          ? _demoTemperatures[_demoReadingIndex]
          : (_decimal('temperature') > 0 ? _decimal('temperature') : 36.6));

  int get _currentSteps => _value('steps') > 0 ? _value('steps') : 4280;

  Future<void> _updateHomeWidget() => HealthHomeWidget.update(
    heartRate: _currentHeartRate,
    oxygenSaturation: _currentSpo2,
    temperature: _currentTemperature,
    isDemo: !_hasRealData,
    updatedAt: DateTime.now(),
  );

  Future<void> _loadLatestWatchReading() async {
    try {
      final reading = await WearOsDataLayer.latest();
      if (reading != null) _onWatchReading(reading);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo consultar BioWatch: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _onWatchReading(Map<String, dynamic> reading) {
    final heartRate = reading['heartRate'];
    final oxygenSaturation = reading['spo2'];
    final temperature = reading['temperature'];
    final updatedAt = reading['updatedAt'];
    final source = reading['source'];
    if (heartRate is! num ||
        updatedAt is! num ||
        source != 'wear_os_sensor' ||
        heartRate < 30 ||
        heartRate > 220) {
      return;
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt());
    if (DateTime.now().difference(timestamp) > const Duration(seconds: 30)) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _watchHeartRate = heartRate.round();
      _watchOxygenSaturation = oxygenSaturation is num
          ? oxygenSaturation.round()
          : null;
      _watchTemperature = temperature is num ? temperature.toDouble() : null;
      _watchUpdatedAt = timestamp;
      _watchSource = source as String;
      final deviceName = reading['deviceName'];
      _watchDeviceName = deviceName is String && deviceName.trim().isNotEmpty
          ? deviceName
          : 'Wear OS';
    });
    unawaited(_updateHomeWidget());
  }

  Future<void> _initializeMeasurements() async {
    if (widget.isDemo) return;
    try {
      await _measurementRepository.initialize();
      _measurementSubscription = _measurementRepository
          .watchMeasurements()
          .listen(
            (items) {
              if (mounted) {
                setState(() {
                  _savedMeasurements = items;
                  _measurementError = null;
                });
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('No se pudo consultar el historial: $error');
              debugPrintStack(stackTrace: stackTrace);
              if (mounted) setState(() => _measurementError = '$error');
            },
          );
    } catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el historial de mediciones: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _measurementError = '$error');
    }
  }

  Future<void> _saveCurrentMeasurement() async {
    if (!_canSaveMeasurement) return;
    final bluetooth = _wearableBluetooth.isConnected;
    final readingAt = bluetooth ? _wearableUpdatedAt! : _watchUpdatedAt!;
    final draft = WearableMeasurementDraft(
      readingAt: readingAt,
      source: bluetooth ? 'ble_hr' : 'wear_os_sensor',
      deviceName: bluetooth
          ? (_wearableBluetooth.deviceName ?? 'Dispositivo BLE')
          : (_watchDeviceName ?? 'Wear OS'),
      heartRateBpm: bluetooth
          ? _wearableBluetooth.heartRate!
          : _watchHeartRate!,
      oxygenSaturationPercent: bluetooth
          ? _wearableBluetooth.oxygenSaturation?.round()
          : _watchOxygenSaturation,
      bodyTemperatureCelsius: bluetooth
          ? _wearableBluetooth.temperature
          : _watchTemperature,
    );
    setState(() => _savingMeasurement = true);
    try {
      final id = await _measurementRepository.saveMeasurement(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Medición $id guardada en PostgreSQL.')),
        );
      }
    } on MeasurementStoreException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la medición: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMeasurement = false);
    }
  }

  Future<void> _openReminderSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReminderSettingsScreen()),
    );
  }

  Future<void> _restoreReminders() async {
    try {
      final medications = await _reminderRepository.loadMedicationReminders();
      final settings = await _reminderRepository.loadMeasurementSettings();
      await _reminderScheduler.sync(
        medications: medications,
        measurementSettings: settings,
        requestPermission: false,
      );
    } catch (error, stackTrace) {
      debugPrint('No se pudieron restaurar los recordatorios: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _refreshWatchFreshness() {
    if (!mounted || _watchUpdatedAt == null) return;
    final wasConnected = _watchIsConnected;
    final isConnected =
        DateTime.now().difference(_watchUpdatedAt!) <
        const Duration(seconds: 10);
    if (wasConnected != isConnected) setState(() {});
  }

  Future<void> _requestHomeWidget() async {
    try {
      final requested = await HealthHomeWidget.requestPin();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requested
                ? 'Confirma en tu pantalla de inicio para añadir BioMedica.'
                : 'Tu pantalla de inicio no permite añadir widgets desde la app. '
                      'Agrégalo desde el selector de widgets.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo solicitar el widget: $error')),
      );
    }
  }

  int _value(String key, [int fallback = 0]) {
    final value = _telemetry[key];
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  double _decimal(String key, [double fallback = 0]) {
    final value = _telemetry[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  List<int> get _chartValues {
    final values = _history
        .map((point) => _readNumber(point, 'heartRate', 0))
        .where((value) => value > 0)
        .toList();
    final bluetoothRate = _wearableBluetooth.heartRate;
    if (bluetoothRate != null) values.add(bluetoothRate);
    return values.length > 1 ? values : _demoRates;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _home(),
      _historyPage(),
      _reportsPage(),
      _turnPage(),
      _profilePage(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            backgroundColor: BioMedicaColors.surface,
            indicatorColor: BioMedicaColors.primaryLight,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_rounded),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description_rounded),
                label: 'Reportes',
              ),
              NavigationDestination(
                icon: Icon(Icons.confirmation_number_outlined),
                selectedIcon: Icon(Icons.confirmation_number_rounded),
                label: 'Mi turno',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportsPage() => ReportsScreen(
    patientName: widget.patientName,
    chronicConditions: widget.chronicConditions,
  );

  Widget _home() => _scroll([
    _topBar(),
    const SizedBox(height: 22),
    Text(
      'Hola, ${widget.patientName.split(' ').first}',
      style: const TextStyle(
        color: BioMedicaColors.ink,
        fontSize: 27,
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: 4),
    const Text(
      'Este es el resumen de hoy.',
      style: TextStyle(color: BioMedicaColors.muted, fontSize: 14),
    ),
    const SizedBox(height: 17),
    _dataNotice(),
    const SizedBox(height: 10),
    _sectionTitle(
      'Mis signos vitales',
      action: 'Añadir widget',
      onTap: _requestHomeWidget,
    ),
    const SizedBox(height: 8),
    _vitalsDashboard(),
    const SizedBox(height: 10),
    _activityCard(),
    const SizedBox(height: 20),
    _sectionTitle('Dispositivo', action: 'Vincular', onTap: _wearableSheet),
    const SizedBox(height: 9),
    _wearableCard(),
    const SizedBox(height: 8),
    FilledButton.icon(
      key: const ValueKey('saveMeasurement'),
      onPressed: _canSaveMeasurement ? _saveCurrentMeasurement : null,
      icon: _savingMeasurement
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_alt_rounded),
      label: const Text('Guardar medición real'),
    ),
    const SizedBox(height: 4),
    const Text(
      'Solo se guardan lecturas recientes del sensor; los datos de muestra no se registran.',
      style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
    ),
    const SizedBox(height: 20),
    _sectionTitle(
      'Reportes de salud',
      action: 'Ver reportes',
      onTap: () => setState(() => _tab = 2),
    ),
    const SizedBox(height: 9),
    const Text(
      'Guarda y consulta reportes privados almacenados en Firestore.',
      style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
    ),
    const SizedBox(height: 20),
    _sectionTitle(
      'Tu turno',
      action: 'Ver turno',
      onTap: () => setState(() => _tab = 3),
    ),
    const SizedBox(height: 9),
    _turnSummary(),
    const SizedBox(height: 24),
  ], label: 'Resumen de salud');

  Widget _topBar() => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: BioMedicaColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.monitor_heart_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'BioMedica',
        style: TextStyle(
          color: BioMedicaColors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      const Spacer(),
      IconButton(
        tooltip: 'Actualizar datos',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
        style: IconButton.styleFrom(
          backgroundColor: BioMedicaColors.surface,
          foregroundColor: BioMedicaColors.ink,
        ),
      ),
    ],
  );

  Widget _dataNotice() {
    final live = _hasRealData;
    final fromWatch = _watchIsConnected;
    final color = live
        ? BioMedicaColors.green
        : fromWatch
        ? BioMedicaColors.primary
        : const Color(0xFF80530C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: live
            ? BioMedicaColors.greenLight
            : fromWatch
            ? BioMedicaColors.primaryLight
            : const Color(0xFFFFF5E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: live
              ? const Color(0xFFC8E8D8)
              : fromWatch
              ? const Color(0xFFCCD9F7)
              : const Color(0xFFF1DFB9),
        ),
      ),
      child: Row(
        children: [
          Icon(
            live
                ? Icons.sensors_rounded
                : fromWatch
                ? Icons.watch_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              live
                  ? _wearableBluetooth.isConnected
                        ? 'Lecturas recibidas directamente por Bluetooth.'
                        : 'Lecturas recibidas desde BioMedica.'
                  : fromWatch
                  ? 'Datos de muestra recibidos desde BioWatch. No son mediciones reales.'
                  : 'Datos de demostración. No son mediciones reales.',
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitalsDashboard() => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 9.0;
      final cardWidth = (constraints.maxWidth - spacing * 2) / 3;
      final diameter = (cardWidth * 0.56).clamp(42.0, 64.0);
      return Row(
        children: [
          SizedBox(
            width: cardWidth,
            child: VitalIndicatorCard(
              label: 'Frecuencia cardiaca',
              value: '$_currentHeartRate',
              unit: 'BPM',
              progress: _currentHeartRate / 180,
              color: BioMedicaColors.red,
              diameter: diameter,
            ),
          ),
          const SizedBox(width: spacing),
          SizedBox(
            width: cardWidth,
            child: VitalIndicatorCard(
              label: 'Oxigenación',
              value: '$_currentSpo2',
              unit: 'SpO₂ %',
              progress: _currentSpo2 / 100,
              color: BioMedicaColors.teal,
              diameter: diameter,
            ),
          ),
          const SizedBox(width: spacing),
          Expanded(
            child: VitalIndicatorCard(
              label: 'Temperatura',
              value: _currentTemperature.toStringAsFixed(1),
              unit: '°C',
              progress: (_currentTemperature - 34) / 8,
              color: BioMedicaColors.primary,
              diameter: diameter,
            ),
          ),
        ],
      );
    },
  );

  Widget _activityCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: BioMedicaColors.line),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.directions_walk_rounded,
          color: BioMedicaColors.primary,
          size: 21,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Actividad de hoy',
            style: TextStyle(
              color: BioMedicaColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$_currentSteps pasos',
          style: const TextStyle(
            color: BioMedicaColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _wearableCard() {
    final connected = _wearableBluetooth.isConnected;
    final title = connected
        ? (_wearableBluetooth.deviceName ?? 'Wearable conectado')
        : _hasRealData
        ? 'Wearable conectado'
        : _watchIsConnected
        ? 'BioWatch del emulador conectado'
        : _demoWearableLinked
        ? 'BioWatch de demostración'
        : 'Sin wearable vinculado';
    final subtitle = connected
        ? '${_wearableBluetooth.readings.length} características BLE detectadas'
        : _hasRealData
        ? 'Última sincronización reciente'
        : _watchIsConnected
        ? 'Datos de muestra recibidos cada 3 segundos'
        : _demoWearableLinked
        ? 'Lecturas simuladas actualizándose en este teléfono'
        : 'Conecta tu dispositivo para comenzar';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BioMedicaColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: BioMedicaColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.watch_rounded,
              color: BioMedicaColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: BioMedicaColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: connected
                ? 'Desconectar wearable'
                : _demoWearableLinked
                ? 'Detener datos de demostración'
                : 'Vincular wearable',
            onPressed: connected
                ? _wearableBluetooth.disconnect
                : _demoWearableLinked
                ? _stopDemoTelemetry
                : _wearableSheet,
            icon: Icon(
              connected
                  ? Icons.link_off_rounded
                  : _demoWearableLinked
                  ? Icons.stop_circle_outlined
                  : Icons.add_circle_outline_rounded,
            ),
            color: connected ? BioMedicaColors.red : BioMedicaColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _turnSummary() => InkWell(
    onTap: () => setState(() => _tab = 3),
    borderRadius: BorderRadius.circular(14),
    child: const TurnStatusHero(
      ticketNumber: 'B-024',
      status: 'En espera',
      service: 'Consulta general',
      room: 'Sala 2',
      estimatedWait: '18 min',
      peopleAhead: 3,
    ),
  );

  Widget _historyPage() {
    final demo = !_hasRealData || _history.isEmpty;
    final rows = demo ? _demoHistory() : _history.reversed.toList();
    return _scroll([
      _pageHeader('Historial', 'Revisa tus lecturas recientes.'),
      const SizedBox(height: 16),
      _dataNotice(),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: BioMedicaColors.surface,
          border: Border.all(color: BioMedicaColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Frecuencia cardiaca',
              style: TextStyle(
                color: BioMedicaColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 145,
              width: double.infinity,
              child: CustomPaint(
                painter: _LinePainter(
                  _chartValues,
                  BioMedicaColors.primary,
                  grid: true,
                ),
              ),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '08:00',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 10),
                ),
                Text(
                  '12:00',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 10),
                ),
                Text(
                  '16:00',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 10),
                ),
                Text(
                  'Ahora',
                  style: TextStyle(color: BioMedicaColors.muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle('Registros', action: 'Actualizar', onTap: _refresh),
      const SizedBox(height: 9),
      ...rows.map((entry) => _historyRow(entry, demo)),
      const SizedBox(height: 18),
      const Text(
        'Mediciones guardadas',
        style: TextStyle(
          color: BioMedicaColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      if (_measurementError case final error?)
        Text(
          'No se pudo cargar el historial de mediciones: $error',
          style: const TextStyle(color: BioMedicaColors.red, fontSize: 12),
        )
      else if (_savedMeasurements.isEmpty)
        const Text(
          'Aún no hay mediciones guardadas.',
          style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
        )
      else
        ..._savedMeasurements.map(_measurementTile),
      const SizedBox(height: 9),
      const Text(
        'Estas lecturas son datos registrados y no constituyen un diagnóstico médico.',
        style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
      ),
      const SizedBox(height: 20),
    ], label: 'Historial de signos');
  }

  Widget _measurementTile(WearableMeasurement measurement) {
    final date = measurement.readingAt.toLocal();
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final optionalVitals = [
      if (measurement.oxygenSaturationPercent case final spo2?) 'SpO₂ $spo2%',
      if (measurement.bodyTemperatureCelsius case final temperature?)
        'Temperatura ${temperature.toStringAsFixed(1)} °C',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BioMedicaColors.line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.favorite_outline_rounded,
            color: BioMedicaColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${measurement.heartRateBpm} BPM'
                  '${optionalVitals.isEmpty ? '' : ' · ${optionalVitals.join(' · ')}'}',
                  style: const TextStyle(
                    color: BioMedicaColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$dateText · ${measurement.deviceName}',
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> entry, bool demo) {
    final rate = _readNumber(entry, 'heartRate', 72);
    final oxygen = _readNumber(entry, 'spo2', 98);
    final temperature = _readDouble(
      entry,
      'temperature',
      36.6,
    ).toStringAsFixed(1);
    final rawDate = entry['timestamp'];
    final parsed = DateTime.tryParse('$rawDate');
    final time = parsed == null
        ? (rawDate?.toString() ?? 'Hoy')
        : '${parsed.toLocal().hour.toString().padLeft(2, '0')}:${parsed.toLocal().minute.toString().padLeft(2, '0')}';
    return HistoryReadingTile(
      heartRate: rate,
      oxygenSaturation: oxygen,
      temperature: temperature,
      time: time,
      isDemo: demo,
    );
  }

  Widget _turnPage() => _scroll([
    _pageHeader('Mi turno', 'Consulta el estado de tu atención.'),
    const SizedBox(height: 17),
    const TurnQueueDemo(),
    const SizedBox(height: 22),
    const Text(
      '¿Cómo funciona?',
      style: TextStyle(color: BioMedicaColors.ink, fontWeight: FontWeight.w800),
    ),
    const SizedBox(height: 12),
    const _Step(
      number: '1',
      title: 'Espera tu llamado',
      detail: 'El panel de sala mostrará tu turno.',
    ),
    const _Step(
      number: '2',
      title: 'Acércate a la sala',
      detail: 'Dirígete a Sala 2 cuando aparezca tu número.',
    ),
    const _Step(
      number: '3',
      title: 'Inicia tu consulta',
      detail: 'El personal actualizará el estado al atenderte.',
    ),
    const SizedBox(height: 22),
  ], label: 'Mi turno');

  Widget _profilePage() => _scroll([
    _pageHeader('Perfil', 'Tu información de paciente.'),
    const SizedBox(height: 18),
    Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BioMedicaColors.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: BioMedicaColors.primaryLight,
            child: Text(
              widget.patientName[0].toUpperCase(),
              style: const TextStyle(
                color: BioMedicaColors.primary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patientName,
                  style: const TextStyle(
                    color: BioMedicaColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.patientEmail,
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 15),
    _profileItem(
      Icons.watch_outlined,
      'Wearable',
      _demoWearableLinked ? 'BioWatch demo' : 'Sin vincular',
    ),
    OutlinedButton.icon(
      onPressed: _openReminderSettings,
      icon: const Icon(Icons.notifications_active_outlined),
      label: const Text('Medicamentos y recordatorio de medición'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    _profileItem(
      Icons.shield_outlined,
      'Privacidad',
      'Datos de salud sensibles',
    ),
    const SizedBox(height: 14),
    OutlinedButton.icon(
      onPressed: widget.onSignOut,
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: const Text('Cerrar sesión'),
      style: OutlinedButton.styleFrom(
        foregroundColor: BioMedicaColors.red,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Color(0xFFE7C9CD)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    const SizedBox(height: 18),
    const Text(
      'Prototipo BioMedica · aplicación del paciente',
      textAlign: TextAlign.center,
      style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
    ),
  ], label: 'Perfil');

  Widget _profileItem(IconData icon, String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: BioMedicaColors.line),
    ),
    child: Row(
      children: [
        Icon(icon, color: BioMedicaColors.primary, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: BioMedicaColors.ink, fontSize: 12),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: BioMedicaColors.muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _pageHeader(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _topBar(),
      const SizedBox(height: 24),
      Text(
        title,
        style: const TextStyle(
          color: BioMedicaColors.ink,
          fontSize: 27,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(color: BioMedicaColors.muted, fontSize: 14),
      ),
    ],
  );

  Widget _scroll(List<Widget> children, {String label = ''}) => Semantics(
    label: label,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 11, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _sectionTitle(String title, {String? action, VoidCallback? onTap}) =>
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: BioMedicaColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              ),
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      );

  List<Map<String, dynamic>> _demoHistory() => [
    {'heartRate': 72, 'spo2': 98, 'temperature': 36.5, 'timestamp': '08:15'},
    {'heartRate': 75, 'spo2': 98, 'temperature': 36.6, 'timestamp': '10:30'},
    {'heartRate': 71, 'spo2': 99, 'temperature': 36.6, 'timestamp': '12:00'},
    {'heartRate': 78, 'spo2': 98, 'temperature': 36.7, 'timestamp': '14:20'},
    {'heartRate': 74, 'spo2': 98, 'temperature': 36.6, 'timestamp': 'Ahora'},
  ];

  int _readNumber(Map<String, dynamic> map, String key, int fallback) {
    final value = map[key];
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  double _readDouble(Map<String, dynamic> map, String key, double fallback) {
    final value = map[key];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  Future<void> _wearableSheet() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SafeArea(
          child: WearablePairingSheet(
            monitor: _wearableBluetooth,
            onUseDemo: () {
              _startDemoTelemetry();
              Navigator.pop(dialogContext);
            },
          ),
        ),
      ),
    );
  }

  void _startDemoTelemetry() {
    _demoTelemetryTimer?.cancel();
    setState(() {
      _demoWearableLinked = true;
      _demoReadingIndex = 0;
    });
    unawaited(_updateHomeWidget());
    _demoTelemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_demoWearableLinked) return;
      setState(() {
        _demoReadingIndex = (_demoReadingIndex + 1) % _demoRates.length;
      });
      unawaited(_updateHomeWidget());
    });
  }

  void _stopDemoTelemetry() {
    _demoTelemetryTimer?.cancel();
    setState(() => _demoWearableLinked = false);
    unawaited(_updateHomeWidget());
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: BioMedicaColors.primaryLight,
          child: Text(
            number,
            style: const TextStyle(
              color: BioMedicaColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: BioMedicaColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.values, this.color, {this.grid = false});
  final List<int> values;
  final Color color;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final low = values.reduce((a, b) => a < b ? a : b) - 4;
    final high = values.reduce((a, b) => a > b ? a : b) + 4;
    final chartHeight = size.height - (grid ? 16 : 4);
    final points = List.generate(
      values.length,
      (i) => Offset(
        size.width * i / (values.length - 1),
        (grid ? 8 : 2) + chartHeight * (1 - (values[i] - low) / (high - low)),
      ),
    );
    if (grid) {
      final paint = Paint()
        ..color = BioMedicaColors.line
        ..strokeWidth = 1;
      for (var row = 0; row < 4; row++) {
        final y = 8 + chartHeight * row / 3;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final middle = (points[i - 1].dx + points[i].dx) / 2;
      path.cubicTo(
        middle,
        points[i - 1].dy,
        middle,
        points[i].dy,
        points[i].dx,
        points[i].dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid;
}
