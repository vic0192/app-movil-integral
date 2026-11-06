import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class IncomingMessageNotifier {
  Future<void> initialize();

  Future<bool> notify(String messageId);
}

class ChatMessageNotificationService implements IncomingMessageNotifier {
  ChatMessageNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool? _permissionGranted;

  @override
  Future<void> initialize() => _initialize();

  @override
  Future<bool> notify(String messageId) async {
    if (kIsWeb) return false;
    await _initialize();
    _permissionGranted ??= await _requestPermission();
    if (!_permissionGranted!) return false;
    await _plugin.show(
      id: _notificationId(messageId),
      title: 'Nuevo mensaje en Mi consulta',
      body: 'Tu equipo médico te envió un mensaje.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'biomedica_clinical_chat',
          'Mensajes de Mi consulta',
          channelDescription: 'Avisos de mensajes del equipo médico',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    return true;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'biomedica_clinical_chat',
        'Mensajes de Mi consulta',
        description: 'Avisos de mensajes del equipo médico',
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  Future<bool> _requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
