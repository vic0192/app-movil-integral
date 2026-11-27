import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bio_medica_colors.dart';
import '../ble/wear_os_data_layer.dart';
import '../data/api_report_repository.dart';
import '../data/clinic_turn_repository.dart';
import '../data/clinical_chat_repository.dart';
import '../data/clinical_video_call_repository.dart';
import '../data/reminder_repository.dart';
import '../data/supabase_measurement_repository.dart';
import '../data/supabase_config.dart';
import '../models/heart_rate_interpretation.dart';
import '../models/health_connect_record.dart';
import '../models/health_report.dart';
import '../models/wearable_measurement.dart';
import '../services/app_lock_service.dart';
import '../services/health_home_widget.dart';
import '../services/chat_message_notification_service.dart';
import '../services/demo_video_call_service.dart';
import '../services/firebase_chat_push_service.dart';
import '../services/local_reminder_scheduler.dart';
import '../widgets/turn_status_hero.dart';
import '../widgets/turn_queue_panel.dart';
import '../widgets/health_connect_home_summary.dart';
import 'reports_screen.dart';
import 'app_lock_screen.dart';
import 'mi_consulta_screen.dart';
import 'reminder_settings_screen.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({
    super.key,
    this.patientUid = '',
    required this.patientName,
    required this.patientEmail,
    this.chronicConditions = const [],
    required this.onSignOut,
    this.isDemo = false,
    this.measurementRepository,
    this.reportRepository,
    this.clinicTurnRepository,
    this.callRepository,
    this.messageNotifier,
    this.appLockService,
    this.appLockEnabled = false,
    this.onAppLockChanged,
  });

  final String patientUid;
  final String patientName;
  final String patientEmail;
  final List<String> chronicConditions;
  final VoidCallback onSignOut;
  final bool isDemo;
  final MeasurementRepository? measurementRepository;
  final ReportRepository? reportRepository;
  final ClinicTurnRepository? clinicTurnRepository;
  final ClinicalVideoCallRepository? callRepository;
  final IncomingMessageNotifier? messageNotifier;
  final AppLockService? appLockService;
  final bool appLockEnabled;
  final ValueChanged<bool>? onAppLockChanged;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  late final MeasurementRepository _measurementRepository =
      widget.measurementRepository ?? SupabaseMeasurementRepository();
  late final ReportRepository _reportRepository =
      widget.reportRepository ?? ApiReportRepository();
  late final ClinicTurnRepository _clinicTurnRepository =
      widget.clinicTurnRepository ?? SupabaseClinicTurnRepository();
  late final ClinicalVideoCallRepository _callRepository =
      widget.callRepository ?? SupabaseClinicalVideoCallRepository();
  late final ClinicalChatRepository _clinicalChatRepository =
      SupabaseClinicalChatRepository();
  late final IncomingMessageNotifier _messageNotifier =
      widget.messageNotifier ?? ChatMessageNotificationService();
  late final AppLockService _appLockService =
      widget.appLockService ?? AppLockService();
  final _reminderRepository = SupabaseReminderRepository();
  final _reminderScheduler = LocalReminderScheduler();
  Timer? _turnRefreshTimer;
  Timer? _watchFreshnessTimer;
  Timer? _watchNodeRefreshTimer;
  StreamSubscription<Map<String, dynamic>>? _watchSubscription;
  StreamSubscription<List<WearableMeasurement>>? _measurementSubscription;
  StreamSubscription<List<HealthReport>>? _reportSubscription;
  StreamSubscription<List<ClinicalConversation>>? _conversationSubscription;
  StreamSubscription<List<ClinicalVideoCall>>? _incomingCallSubscription;
  StreamSubscription<void>? _widgetActionSubscription;
  final Map<String, StreamSubscription<List<ClinicalMessage>>>
  _messageSubscriptions = {};
  final Set<String> _notifiedMessageIds = {};
  final Set<String> _processedWatchCaptureIds = {};
  final Set<String> _watchCaptureIdsInProgress = {};
  final Set<String> _presentedCallIds = {};
  final List<ClinicalVideoCall> _pendingIncomingCalls = [];
  FirebaseChatPushService? _pushService;
  final _chatScreenKey = GlobalKey<MiConsultaScreenState>();
  Stream<List<HealthReport>>? _reportsStream;
  int _tab = 0;
  int? _watchHeartRate;
  int? _watchOxygenSaturation;
  double? _watchTemperature;
  String? _watchDeviceName;
  DateTime? _watchUpdatedAt;
  WearOsNode? _watchNode;
  bool _watchNodeLoading = false;
  bool _refreshingWatchNode = false;
  String? _watchNodeError;
  List<WearableMeasurement> _savedMeasurements = const [];
  String? _measurementError;
  bool _measurementsLoading = true;
  List<HealthConnectRecord> _healthConnectRecords = const [];
  List<HealthReport> _reports = const [];
  String? _reportsError;
  bool _reportsLoading = true;
  ClinicTurn? _patientTurn;
  List<ClinicTurn> _activeTurns = const [];
  String? _turnError;
  bool _turnLoading = true;
  bool _notificationPermissionWarningShown = false;
  bool _incomingCallDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _watchSubscription = WearOsDataLayer.readings.listen(
        _onWatchReading,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('No se pudieron recibir datos de BioWatch: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
      unawaited(_loadLatestWatchReading());
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_refreshWatchNode());
      _watchNodeRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_refreshWatchNode()),
      );
      _widgetActionSubscription = HealthHomeWidget.urgentCallRequests.listen(
        (_) => _handleWidgetUrgentCallRequest(),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('No se pudo recibir la solicitud del widget BioMedica.');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
    }
    unawaited(_initializeReports());
    if (!widget.isDemo && widget.patientUid.isNotEmpty) {
      _startIncomingCallMonitor();
    }
    _startChatNotificationMonitor();
    unawaited(_configurePushNotifications());
    unawaited(_refreshTurns());
    _watchFreshnessTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshWatchFreshness(),
    );
    unawaited(_initializeMeasurements());
    _turnRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshTurns(),
    );
    if (!widget.isDemo) unawaited(_restoreReminders());
  }

  @override
  void dispose() {
    _turnRefreshTimer?.cancel();
    _watchFreshnessTimer?.cancel();
    _watchNodeRefreshTimer?.cancel();
    unawaited(_watchSubscription?.cancel());
    unawaited(_measurementSubscription?.cancel());
    unawaited(_reportSubscription?.cancel());
    unawaited(_conversationSubscription?.cancel());
    unawaited(_incomingCallSubscription?.cancel());
    unawaited(_widgetActionSubscription?.cancel());
    for (final subscription in _messageSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    unawaited(_pushService?.dispose());
    super.dispose();
  }

  void _onHealthConnectRecordsLoaded(List<HealthConnectRecord> records) {
    if (!mounted) return;
    setState(() => _healthConnectRecords = List.of(records));
    unawaited(_updateHomeWidget());
  }

  void _handleWidgetUrgentCallRequest() {
    if (!mounted) return;
    setState(() => _tab = 5);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chatScreen = _chatScreenKey.currentState;
      if (chatScreen != null) unawaited(chatScreen.requestUrgentCall());
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      _initializeMeasurements(),
      _initializeReports(),
      _refreshTurns(),
    ]);
  }

  Future<void> _refreshCurrentTab() async {
    switch (_tab) {
      case 0:
        await _refresh();
        break;
      case 1:
        await _initializeMeasurements();
        break;
      case 2:
        await _initializeReports();
        break;
      case 3:
        await _refreshTurns();
        break;
      case 4:
        await _refresh();
        break;
      case 5:
        await _chatScreenKey.currentState?.refresh();
        break;
    }
  }

  void _startChatNotificationMonitor() {
    if (widget.isDemo || widget.patientUid.isEmpty) return;
    try {
      _conversationSubscription = _clinicalChatRepository
          .watchConversations()
          .listen(
            (conversations) {
              final activeIds = conversations
                  .map((conversation) => conversation.id)
                  .toSet();
              for (final id in _messageSubscriptions.keys.toList()) {
                if (!activeIds.contains(id)) {
                  unawaited(_messageSubscriptions.remove(id)?.cancel());
                }
              }
              for (final conversation in conversations) {
                if (_messageSubscriptions.containsKey(conversation.id)) {
                  continue;
                }
                _watchConversationMessages(conversation.id);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('No se pudieron monitorear los chats: $error');
              debugPrintStack(stackTrace: stackTrace);
            },
          );
    } catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el monitoreo de chats: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _watchConversationMessages(String conversationId) {
    var initialSnapshot = true;
    try {
      final subscription = _clinicalChatRepository
          .watchMessages(conversationId)
          .listen(
            (messages) {
              if (initialSnapshot) {
                initialSnapshot = false;
                return;
              }
              for (final message in messages) {
                if (message.senderUid != widget.patientUid) {
                  _handleIncomingMessage(message.id);
                }
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('No se pudo monitorear la conversación: $error');
              debugPrintStack(stackTrace: stackTrace);
            },
          );
      _messageSubscriptions[conversationId] = subscription;
    } catch (error, stackTrace) {
      debugPrint(
        'No se pudo abrir la conversación para notificaciones: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _startIncomingCallMonitor() {
    try {
      _incomingCallSubscription = _callRepository.watchIncomingCalls().listen(
        (calls) {
          for (final call in calls) {
            if (_presentedCallIds.add(call.id)) {
              _pendingIncomingCalls.add(call);
            }
          }
          unawaited(_showNextIncomingCall());
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Could not monitor incoming clinical calls.');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Could not start incoming clinical call monitoring.');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _showNextIncomingCall() async {
    if (!mounted || _incomingCallDialogOpen || _pendingIncomingCalls.isEmpty) {
      return;
    }
    final call = _pendingIncomingCalls.removeAt(0);
    _incomingCallDialogOpen = true;
    try {
      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Llamada de consulta'),
          content: const Text(
            'El equipo médico te invita a una videollamada. Al aceptar, se '
            'abrirá una sala pública de demostración. No compartas información '
            'clínica o personal en esa sala.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Rechazar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.video_call_outlined),
              label: const Text('Unirme'),
            ),
          ],
        ),
      );
      if (!mounted || accept == null) return;
      await _callRepository.respondToCall(call.id, accept: accept);
      if (!accept) return;
      final opened = await DemoVideoCallService.openInvite(call.inviteUrl);
      if (!opened && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir la sala. Solicita otra invitación.',
            ),
          ),
        );
      }
    } on ClinicalVideoCallException catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      debugPrint('Could not respond to an incoming clinical call.');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la llamada. Inténtalo de nuevo.'),
          ),
        );
      }
    } finally {
      _incomingCallDialogOpen = false;
      if (mounted && _pendingIncomingCalls.isNotEmpty) {
        unawaited(_showNextIncomingCall());
      }
    }
  }

  Future<void> _configurePushNotifications() async {
    if (widget.isDemo ||
        kIsWeb ||
        !FirebaseChatPushService.enabled ||
        !SupabaseConfig.isConfigured) {
      return;
    }
    final service = FirebaseChatPushService(
      supabaseClient: Supabase.instance.client,
      onMessageReceived: _handleIncomingMessage,
      onNotificationOpened: () {
        if (mounted) setState(() => _tab = 5);
      },
    );
    _pushService = service;
    try {
      await _messageNotifier.initialize();
      await service.initialize();
    } catch (error, stackTrace) {
      debugPrint('No se pudo configurar Firebase Messaging: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _handleIncomingMessage(String messageId) {
    if (messageId.isEmpty || _notifiedMessageIds.contains(messageId)) return;
    if (_notifiedMessageIds.length >= 500) {
      _notifiedMessageIds.remove(_notifiedMessageIds.first);
    }
    _notifiedMessageIds.add(messageId);
    unawaited(_notifyIncomingMessage(messageId));
  }

  Future<void> _notifyIncomingMessage(String messageId) async {
    if (kIsWeb) return;
    try {
      final shown = await _messageNotifier.notify(messageId);
      if (!shown && mounted && !_notificationPermissionWarningShown) {
        _notificationPermissionWarningShown = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Activa las notificaciones para recibir avisos de Mi consulta.',
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo mostrar la notificación de chat: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _signOut() async {
    final service = _pushService;
    if (service != null) {
      try {
        await service.unregister();
      } catch (error, stackTrace) {
        debugPrint('No se pudo desvincular el token de notificaciones: $error');
        debugPrintStack(stackTrace: stackTrace);
      } finally {
        await service.dispose();
        _pushService = null;
      }
    }
    widget.onSignOut();
  }

  Future<void> _refreshTurns() async {
    if (mounted) setState(() => _turnLoading = true);
    try {
      final results = await Future.wait([
        _clinicTurnRepository.loadMyActiveTurn(),
        _clinicTurnRepository.loadActiveQueue(),
      ]);
      if (!mounted) return;
      setState(() {
        _patientTurn = results[0] as ClinicTurn?;
        _activeTurns = results[1] as List<ClinicTurn>;
        _turnError = null;
        _turnLoading = false;
      });
    } catch (error) {
      debugPrint('Could not load clinic turn status.');
      if (mounted) {
        setState(() {
          _turnError = 'No se pudieron cargar los turnos. Inténtalo de nuevo.';
          _turnLoading = false;
        });
      }
    }
  }

  Future<void> _initializeReports() async {
    if (widget.isDemo) {
      if (mounted) setState(() => _reportsLoading = false);
      return;
    }
    await _reportSubscription?.cancel();
    if (mounted) setState(() => _reportsLoading = true);
    try {
      await _reportRepository.initialize();
      final reportsStream = _reportRepository
          .watchReports()
          .asBroadcastStream();
      _reportsStream = reportsStream;
      _reportSubscription = reportsStream.listen(
        (reports) {
          if (mounted) {
            setState(() {
              _reports = reports;
              _reportsError = null;
              _reportsLoading = false;
            });
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('No se pudieron consultar los reportes: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (mounted) {
            setState(() {
              _reportsError =
                  'No se pudieron cargar los reportes. Inténtalo de nuevo.';
              _reportsLoading = false;
            });
          }
        },
      );
    } catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el servicio de reportes: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _reportsError =
              'No se pudieron cargar los reportes. Inténtalo de nuevo.';
          _reportsLoading = false;
        });
      }
    }
  }

  bool get _hasRealData =>
      (_watchIsConnected && _watchHeartRate != null) ||
      _savedMeasurements.isNotEmpty ||
      (!kIsWeb && _healthConnectRecords.isNotEmpty);

  bool get _watchIsConnected =>
      _watchUpdatedAt != null &&
      DateTime.now().difference(_watchUpdatedAt!) < const Duration(seconds: 20);

  WearableMeasurement? get _latestSavedMeasurement {
    for (final measurement in _savedMeasurements) {
      if (measurement.source == 'wear_os_sensor') return measurement;
    }
    return null;
  }

  int? get _currentHeartRate {
    if (_watchIsConnected && _watchHeartRate != null) return _watchHeartRate;
    return _latestSavedMeasurement?.heartRateBpm;
  }

  _VitalReading? get _spo2Reading {
    final watchTime = _watchUpdatedAt;
    if (_watchIsConnected &&
        _watchOxygenSaturation != null &&
        watchTime != null) {
      return _VitalReading(
        value: _watchOxygenSaturation!.toDouble(),
        recordedAt: watchTime,
        source: _watchDeviceName ?? 'Wear OS',
      );
    }

    final savedMeasurement = _latestSavedMeasurement;
    final savedValue = savedMeasurement?.oxygenSaturationPercent;
    final savedReading = savedMeasurement == null || savedValue == null
        ? null
        : _VitalReading(
            value: savedValue.toDouble(),
            recordedAt: savedMeasurement.readingAt,
            source: savedMeasurement.deviceName,
          );
    return _newerVitalReading(
      savedReading,
      _healthConnectVital('BLOOD_OXYGEN'),
    );
  }

  _VitalReading? get _temperatureReading {
    final watchTime = _watchUpdatedAt;
    if (_watchIsConnected && _watchTemperature != null && watchTime != null) {
      return _VitalReading(
        value: _watchTemperature!,
        recordedAt: watchTime,
        source: _watchDeviceName ?? 'Wear OS',
      );
    }

    final savedMeasurement = _latestSavedMeasurement;
    final savedValue = savedMeasurement?.bodyTemperatureCelsius;
    final savedReading = savedMeasurement == null || savedValue == null
        ? null
        : _VitalReading(
            value: savedValue,
            recordedAt: savedMeasurement.readingAt,
            source: savedMeasurement.deviceName,
          );
    return _newerVitalReading(
      savedReading,
      _healthConnectVital('BODY_TEMPERATURE'),
    );
  }

  int? get _currentSpo2 => _spo2Reading?.value.round();

  ({HealthConnectRecord systolic, HealthConnectRecord diastolic})?
  get _bloodPressurePair {
    final systolic = _latestHealthConnectRecord('BLOOD_PRESSURE_SYSTOLIC');
    final diastolic = _latestHealthConnectRecord('BLOOD_PRESSURE_DIASTOLIC');
    if (systolic == null || diastolic == null) return null;
    if (systolic.recordedAt.difference(diastolic.recordedAt).inSeconds.abs() >
        120) {
      return null;
    }
    return (systolic: systolic, diastolic: diastolic);
  }

  String? get _currentBloodPressure {
    final pair = _bloodPressurePair;
    if (pair == null) return null;
    return '${pair.systolic.value.round()}/${pair.diastolic.value.round()}';
  }

  DateTime? get _bloodPressureRecordedAt {
    final pair = _bloodPressurePair;
    if (pair == null) return null;
    return pair.systolic.recordedAt.isAfter(pair.diastolic.recordedAt)
        ? pair.systolic.recordedAt
        : pair.diastolic.recordedAt;
  }

  HealthConnectRecord? _latestHealthConnectRecord(String dataType) {
    HealthConnectRecord? latest;
    for (final record in _healthConnectRecords) {
      if (record.dataType == dataType &&
          (latest == null || record.recordedAt.isAfter(latest.recordedAt))) {
        latest = record;
      }
    }
    return latest;
  }

  _VitalReading? _healthConnectVital(String dataType) {
    if (kIsWeb) return null;
    final record = _latestHealthConnectRecord(dataType);
    if (record == null) return null;
    return _VitalReading(
      value: record.value,
      recordedAt: record.recordedAt,
      source: record.sourceName.isEmpty ? 'Health Connect' : record.sourceName,
    );
  }

  _VitalReading? _newerVitalReading(
    _VitalReading? savedReading,
    _VitalReading? healthConnectReading,
  ) {
    if (savedReading == null) return healthConnectReading;
    if (healthConnectReading == null ||
        savedReading.recordedAt.isAfter(healthConnectReading.recordedAt)) {
      return savedReading;
    }
    return healthConnectReading;
  }

  Future<void> _updateHomeWidget() {
    final readingTimes = <DateTime>[
      ?(_watchIsConnected ? _watchUpdatedAt : null),
      ?_latestSavedMeasurement?.readingAt,
      ?_spo2Reading?.recordedAt,
      ?_bloodPressureRecordedAt,
    ];
    final readingAt = readingTimes.isEmpty
        ? null
        : readingTimes.reduce(
            (latest, candidate) =>
                candidate.isAfter(latest) ? candidate : latest,
          );
    return HealthHomeWidget.update(
      heartRate: _currentHeartRate,
      oxygenSaturation: _currentSpo2,
      bloodPressure: _currentBloodPressure,
      updatedAt: readingAt,
    );
  }

  Future<void> _loadLatestWatchReading() async {
    try {
      final reading = await WearOsDataLayer.latest();
      if (reading != null) _onWatchReading(reading);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo consultar BioWatch: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _refreshWatchNode({bool showLoading = false}) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _refreshingWatchNode) {
      return;
    }

    _refreshingWatchNode = true;
    if (showLoading && mounted) {
      setState(() => _watchNodeLoading = true);
    }
    try {
      final nodes = await WearOsDataLayer.connectedNodes();
      final samsungWatches = nodes.where(_isSamsungWatchNode).toList()
        ..sort(
          (left, right) =>
              (left.isNearby ? 0 : 1).compareTo(right.isNearby ? 0 : 1),
        );
      final nextNode = samsungWatches.isEmpty ? null : samsungWatches.first;
      if (mounted &&
          (_watchNode?.id != nextNode?.id ||
              _watchNode?.isNearby != nextNode?.isNearby ||
              _watchNodeError != null)) {
        setState(() {
          _watchNode = nextNode;
          _watchNodeError = null;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo consultar la conexión del Galaxy Watch: $error');
      debugPrintStack(stackTrace: stackTrace);
      const message =
          'No se pudo consultar el reloj. Actualiza para reintentar.';
      if (mounted && _watchNodeError != message) {
        setState(() => _watchNodeError = message);
      }
    } finally {
      _refreshingWatchNode = false;
      if (showLoading && mounted) {
        setState(() => _watchNodeLoading = false);
      }
    }
  }

  bool _isSamsungWatchNode(WearOsNode node) {
    final name = node.displayName.toLowerCase();
    return name.contains('galaxy') ||
        name.contains('samsung') ||
        name.contains('sm-r');
  }

  Future<void> _openGalaxyWearable() async {
    try {
      final opened = await WearOsDataLayer.openGalaxyWearable();
      if (!mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se encontró Galaxy Wearable. Instálalo para emparejar el reloj.',
            ),
          ),
        );
      }
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo abrir Galaxy Wearable: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir Galaxy Wearable. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    }
  }

  void _onWatchReading(Map<String, dynamic> reading) {
    final heartRate = reading['heartRate'];
    final oxygenSaturation = reading['spo2'];
    final temperature = reading['temperature'];
    final updatedAt = reading['updatedAt'];
    final source = reading['source'];
    if (updatedAt is! num || source != 'wear_os_sensor') {
      return;
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt());
    final currentTime = DateTime.now();
    final captureId = reading['captureId'];
    if (timestamp.isBefore(currentTime.subtract(wearOsCaptureMaxAge)) ||
        timestamp.isAfter(currentTime.add(const Duration(minutes: 2)))) {
      if (reading['captureRequested'] == true &&
          captureId is String &&
          captureId.isNotEmpty) {
        unawaited(_discardStaleCapture(captureId));
      }
      return;
    }
    final validHeartRate =
        heartRate is num && heartRate >= 30 && heartRate <= 220
        ? heartRate.round()
        : null;

    if (!mounted) return;
    setState(() {
      _watchHeartRate = validHeartRate;
      _watchOxygenSaturation = oxygenSaturation is num
          ? oxygenSaturation.round()
          : null;
      _watchTemperature = temperature is num ? temperature.toDouble() : null;
      _watchUpdatedAt = timestamp;
      final deviceName = reading['deviceName'];
      _watchDeviceName = deviceName is String && deviceName.trim().isNotEmpty
          ? deviceName
          : 'Wear OS';
    });
    unawaited(_updateHomeWidget());

    if (reading['captureRequested'] == true &&
        captureId is String &&
        captureId.isNotEmpty &&
        !_processedWatchCaptureIds.contains(captureId) &&
        _watchCaptureIdsInProgress.add(captureId)) {
      unawaited(_saveWatchCapture(reading, captureId));
    }
  }

  Future<void> _discardStaleCapture(String captureId) async {
    try {
      await WearOsDataLayer.acknowledgeCapture(captureId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La captura venció antes de sincronizarse; vuelve a medir.',
            ),
          ),
        );
      }
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo descartar la captura vencida $captureId: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _initializeMeasurements() async {
    if (widget.isDemo) {
      if (mounted) setState(() => _measurementsLoading = false);
      return;
    }
    await _measurementSubscription?.cancel();
    if (mounted) setState(() => _measurementsLoading = true);
    try {
      await _measurementRepository.initialize();
      _measurementSubscription = _measurementRepository
          .watchMeasurements()
          .listen(
            (items) {
              if (mounted) {
                setState(() {
                  _savedMeasurements = items
                      .where(
                        (measurement) => measurement.source == 'wear_os_sensor',
                      )
                      .toList(growable: false);
                  _measurementError = null;
                  _measurementsLoading = false;
                });
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('No se pudo consultar el historial: $error');
              debugPrintStack(stackTrace: stackTrace);
              if (mounted) {
                setState(() {
                  _measurementError =
                      'No se pudo cargar el historial. Inténtalo de nuevo.';
                  _measurementsLoading = false;
                });
              }
            },
          );
    } catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el historial de mediciones: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _measurementError =
              'No se pudo cargar el historial. Inténtalo de nuevo.';
          _measurementsLoading = false;
        });
      }
    }
  }

  Future<void> _saveWatchCapture(
    Map<String, dynamic> reading,
    String captureId,
  ) async {
    try {
      final draft = WearableMeasurementDraft.fromWatchReading(reading);
      final id = await _measurementRepository.saveMeasurement(draft);
      _processedWatchCaptureIds.add(captureId);
      try {
        await WearOsDataLayer.acknowledgeCapture(captureId);
      } on PlatformException catch (error, stackTrace) {
        debugPrint('No se pudo confirmar la captura $captureId: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Medición guardada. BioMedica interpretará la lectura ($id).',
            ),
          ),
        );
      }
    } on MeasurementStoreException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La medición recibida no es válida. Vuelve a medir.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar la medición. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      _watchCaptureIdsInProgress.remove(captureId);
    }
  }

  Future<void> _openReminderSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReminderSettingsScreen()),
    );
  }

  Future<void> _openAppLockSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppLockSettingsScreen(
          lockService: _appLockService,
          onChanged: (enabled) {
            widget.onAppLockChanged?.call(enabled);
          },
        ),
      ),
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
        const Duration(seconds: 20);
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
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo solicitar el widget. Inténtalo de nuevo.'),
        ),
      );
    }
  }

  List<int> get _chartValues {
    final values = _savedMeasurements
        .map((measurement) => measurement.heartRateBpm)
        .toList(growable: true);
    final currentReading = _watchIsConnected ? _watchHeartRate : null;
    if (currentReading != null) values.insert(0, currentReading);
    return values.reversed.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _home(),
      _historyPage(),
      _reportsPage(),
      _turnPage(),
      _profilePage(),
      MiConsultaScreen(key: _chatScreenKey, patientUid: widget.patientUid),
    ];
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshCurrentTab,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
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
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_rounded),
                label: 'Mi consulta',
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
    repository: _reportRepository,
    reportsStream: _reportsStream,
    initialReports: _reportsLoading ? null : _reports,
  );

  Widget _home() => _scroll([
    _topBar(),
    const SizedBox(height: 18),
    _welcomeCard(),
    const SizedBox(height: 17),
    if (_measurementError != null)
      Text(
        'No se pudieron cargar tus signos vitales. Inténtalo de nuevo.',
        style: const TextStyle(color: BioMedicaColors.red, fontSize: 12),
      )
    else if (!_measurementsLoading && !_hasRealData)
      const Text(
        'Aún no hay mediciones registradas. Realiza una medición desde la app móvil.',
        style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
      ),
    const SizedBox(height: 10),
    _sectionTitle(
      'Última medición',
      action: 'Añadir widget',
      onTap: _requestHomeWidget,
    ),
    const SizedBox(height: 8),
    _measurementInterpretationCard(),
    if (!kIsWeb) ...[
      const SizedBox(height: 18),
      HealthConnectHomeSummary(onRecordsLoaded: _onHealthConnectRecordsLoaded),
      const SizedBox(height: 18),
      _sectionTitle(
        'Galaxy Watch',
        action: defaultTargetPlatform == TargetPlatform.android
            ? 'Actualizar'
            : null,
        onTap: defaultTargetPlatform == TargetPlatform.android
            ? () => _refreshWatchNode(showLoading: true)
            : null,
      ),
      const SizedBox(height: 9),
      _wearableCard(),
      const SizedBox(height: 18),
      _measurementInstructionsCard(),
    ],
    const SizedBox(height: 20),
    _sectionTitle(
      'Reportes de salud',
      action: 'Ver reportes',
      onTap: () => setState(() => _tab = 2),
    ),
    const SizedBox(height: 9),
    _homeReportsSummary(),
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

  Widget _welcomeCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [BioMedicaColors.primary, Color(0xFF2D7BE8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x241858C8),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SEGUIMIENTO PERSONAL',
                style: TextStyle(
                  color: Color(0xFFDCE8FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Hola, ${widget.patientName.split(' ').first}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Tus mediciones se guardan automáticamente.',
                style: TextStyle(color: Color(0xFFEAF1FF), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Image.asset('assets/icon/biomedica_launcher.png'),
        ),
      ],
    ),
  );

  Widget _measurementInterpretationCard() {
    final heartRate = _currentHeartRate;
    final spo2Reading = _spo2Reading;
    final temperatureReading = _temperatureReading;
    final result = HeartRateInterpretation.fromBpm(heartRate);
    final status = result.label;
    final interpretation =
        result.band == HeartRateBand.unavailable &&
            !_watchIsConnected &&
            _watchNode == null
        ? kIsWeb
              ? 'Las mediciones guardadas desde la app móvil aparecerán aquí.'
              : 'Empareja el Galaxy Watch en Galaxy Wearable; BioMedica recibirá sus lecturas automáticamente.'
        : result.message;
    final Color accent;
    final Color background;
    final IconData icon;

    switch (result.band) {
      case HeartRateBand.unavailable:
        accent = BioMedicaColors.primary;
        background = BioMedicaColors.primaryLight;
        icon = Icons.monitor_heart_outlined;
      case HeartRateBand.belowReference:
        accent = const Color(0xFF9A6700);
        background = const Color(0xFFFFF5D6);
        icon = Icons.info_outline_rounded;
      case HeartRateBand.reference:
        accent = BioMedicaColors.green;
        background = BioMedicaColors.greenLight;
        icon = Icons.check_circle_outline_rounded;
      case HeartRateBand.aboveReference:
        accent = BioMedicaColors.red;
        background = BioMedicaColors.redLight;
        icon = Icons.info_outline_rounded;
    }

    final readingAt = _watchIsConnected
        ? _watchUpdatedAt
        : _latestSavedMeasurement?.readingAt;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BioMedicaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: _PulsingVitalIcon(
                  icon: icon,
                  color: accent,
                  active: heartRate != null && _watchIsConnected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Frecuencia cardiaca',
                      style: TextStyle(
                        color: BioMedicaColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: Text(
                        key: ValueKey(heartRate),
                        heartRate == null ? '—' : '$heartRate BPM',
                        style: const TextStyle(
                          color: BioMedicaColors.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (spo2Reading != null || temperatureReading != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (spo2Reading != null)
                  Expanded(
                    child: _importantVital(
                      icon: Icons.air_rounded,
                      label: 'SpO₂',
                      reading: spo2Reading,
                      unit: '%',
                      formatValue: (value) => value.round().toString(),
                    ),
                  ),
                if (spo2Reading != null && temperatureReading != null)
                  const SizedBox(width: 8),
                if (temperatureReading != null)
                  Expanded(
                    child: _importantVital(
                      icon: Icons.thermostat_outlined,
                      label: 'Temperatura',
                      reading: temperatureReading,
                      unit: '°C',
                      formatValue: (value) => value.toStringAsFixed(1),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            interpretation,
            style: const TextStyle(
              color: BioMedicaColors.ink,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (readingAt != null) ...[
            const SizedBox(height: 9),
            Text(
              'Actualizado ${_formatReadingTime(readingAt)}',
              style: const TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 9),
          const Text(
            'Orientación informativa para adultos en reposo; no es un diagnóstico y no sustituye la valoración médica.',
            style: TextStyle(
              color: BioMedicaColors.muted,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _importantVital({
    required IconData icon,
    required String label,
    required _VitalReading reading,
    required String unit,
    required String Function(double) formatValue,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: BioMedicaColors.primaryLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: BioMedicaColors.primary, size: 15),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            key: ValueKey('${reading.recordedAt}:$unit:${reading.value}'),
            '${formatValue(reading.value)} $unit',
            style: const TextStyle(
              color: BioMedicaColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          '${reading.source} · ${_formatReadingTime(reading.recordedAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: BioMedicaColors.muted, fontSize: 9),
        ),
      ],
    ),
  );

  Widget _measurementInstructionsCard() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: BioMedicaColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: BioMedicaColors.line),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.watch_rounded, color: BioMedicaColors.primary),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'Para medir: mantén el reloj firme y quédate quieto; pulsa “Tomar medición” en el reloj. La lectura se enviará y guardará automáticamente en BioMedica.',
            style: TextStyle(
              color: BioMedicaColors.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  String _formatReadingTime(DateTime time) {
    final local = time.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _topBar() => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/icon/biomedica_launcher.png',
          width: 40,
          height: 40,
          fit: BoxFit.cover,
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

  Widget _wearableCard() {
    final watchSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final node = _watchNode;
    final connected = node?.isNearby == true || _watchIsConnected;
    final title =
        _watchDeviceName ?? node?.displayName ?? 'Galaxy Watch no detectado';
    final subtitle = _watchNodeError != null
        ? 'No se pudo consultar el reloj. Actualiza para reintentar.'
        : node?.isNearby == true
        ? 'Conectado · las lecturas del reloj se reciben automáticamente'
        : node != null
        ? 'Emparejado; esperando que el reloj esté cerca'
        : _watchIsConnected
        ? 'Lectura recibida automáticamente del reloj'
        : 'Empareja una vez en Galaxy Wearable; BioMedica lo detectará automáticamente';
    final color = connected ? BioMedicaColors.green : BioMedicaColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BioMedicaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected ? BioMedicaColors.green : BioMedicaColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: connected
                  ? BioMedicaColors.greenLight
                  : BioMedicaColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.watch_rounded, color: color),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BioMedicaColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: !watchSupported
                ? 'La conexión del reloj requiere Android'
                : node == null
                ? 'Abrir Galaxy Wearable'
                : 'Actualizar conexión del reloj',
            onPressed: !watchSupported || _watchNodeLoading
                ? null
                : node == null
                ? _openGalaxyWearable
                : () => _refreshWatchNode(showLoading: true),
            icon: _watchNodeLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    node == null
                        ? Icons.open_in_new_rounded
                        : Icons.refresh_rounded,
                  ),
            color: color,
          ),
        ],
      ),
    );
  }

  Widget _turnSummary() {
    final turn = _patientTurn;
    return InkWell(
      onTap: () => setState(() => _tab = 3),
      borderRadius: BorderRadius.circular(14),
      child: turn != null
          ? TurnStatusHero(
              ticketNumber: turn.ticketCode,
              status: turn.status == 'en_atencion'
                  ? 'En consulta'
                  : 'En espera',
              service: turn.service,
              room: turn.room,
              estimatedWait: turn.status == 'en_atencion'
                  ? 'Ahora'
                  : '${turn.etaMinutes} min',
              peopleAhead: 0,
              progress: turn.status == 'en_atencion' ? 1 : 0,
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BioMedicaColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BioMedicaColors.line),
              ),
              child: Text(
                _turnError ??
                    (_turnLoading
                        ? 'Consultando tu turno...'
                        : 'No tienes un turno activo asignado.'),
                style: const TextStyle(
                  color: BioMedicaColors.muted,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }

  Widget _homeReportsSummary() {
    if (_reportsError != null) {
      return Text(
        'No se pudieron cargar tus reportes. Inténtalo de nuevo.',
        style: const TextStyle(color: BioMedicaColors.red, fontSize: 12),
      );
    }
    if (_reportsLoading) {
      return const Text(
        'Consultando tus reportes de salud...',
        style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
      );
    }
    if (_reports.isEmpty) {
      return const Text(
        'Aún no tienes reportes de salud.',
        style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
      );
    }
    final latest = _reports.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_reports.length} ${_reports.length == 1 ? 'reporte' : 'reportes'} · '
          '${latest.reviewStatus == 'reviewed' ? 'Revisado' : 'Pendiente de revisión'}',
          style: const TextStyle(
            color: BioMedicaColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (latest.reviewObservations?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Observaciones: ${latest.reviewObservations}',
              style: const TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _historyPage() => _scroll([
    _pageHeader('Historial', 'Revisa tus lecturas recientes.'),
    const SizedBox(height: 16),
    if (_measurementsLoading)
      const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      )
    else if (_measurementError != null)
      Text(
        'No se pudo cargar el historial. Inténtalo de nuevo.',
        style: const TextStyle(color: BioMedicaColors.red, fontSize: 12),
      )
    else if (_savedMeasurements.isEmpty)
      const Text(
        'Aún no hay mediciones guardadas.',
        style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
      )
    else ...[
      if (_chartValues.length > 1)
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
            ],
          ),
        ),
      const SizedBox(height: 20),
    ],
    _sectionTitle(
      'Registros',
      action: 'Actualizar',
      onTap: _initializeMeasurements,
    ),
    const SizedBox(height: 9),
    ..._savedMeasurements.map(_measurementTile),
    const SizedBox(height: 9),
    const Text(
      'Estas lecturas son datos registrados y no constituyen un diagnóstico médico.',
      style: TextStyle(color: BioMedicaColors.muted, fontSize: 11),
    ),
    const SizedBox(height: 20),
  ], label: 'Historial de signos');

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

  Widget _turnPage() => _scroll([
    _pageHeader('Mi turno', 'Consulta el estado de tu atención.'),
    const SizedBox(height: 17),
    TurnQueuePanel(
      patientTurn: _patientTurn,
      activeQueue: _activeTurns,
      loading: _turnLoading,
      error: _turnError,
      onRefresh: _refreshTurns,
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
      'Galaxy Watch',
      _watchDeviceName ?? _watchNode?.displayName ?? 'No detectado',
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
    OutlinedButton.icon(
      onPressed: _openAppLockSettings,
      icon: Icon(
        widget.appLockEnabled ? Icons.lock_rounded : Icons.lock_outline_rounded,
      ),
      label: Text(
        widget.appLockEnabled
            ? 'Contraseña de la app · Activada'
            : 'Configurar contraseña de la app',
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    const SizedBox(height: 14),
    OutlinedButton.icon(
      onPressed: () => unawaited(_signOut()),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
}

class _VitalReading {
  const _VitalReading({
    required this.value,
    required this.recordedAt,
    required this.source,
  });

  final double value;
  final DateTime recordedAt;
  final String source;
}

class _PulsingVitalIcon extends StatefulWidget {
  const _PulsingVitalIcon({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  State<_PulsingVitalIcon> createState() => _PulsingVitalIconState();
}

class _PulsingVitalIconState extends State<_PulsingVitalIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _PulsingVitalIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Icon(widget.icon, color: widget.color),
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
