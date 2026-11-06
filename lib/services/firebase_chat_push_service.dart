import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/core_api_client.dart';

class FirebaseChatPushService {
  FirebaseChatPushService({
    required SupabaseClient supabaseClient,
    required this.onMessageReceived,
    required this.onNotificationOpened,
  }) : _api = CoreApiClient(
         accessTokenProvider: () async =>
             supabaseClient.auth.currentSession?.accessToken,
         accessTokenRefresher: () async {
           final refreshed = await supabaseClient.auth.refreshSession();
           return refreshed.session?.accessToken;
         },
       );

  static const enabled = bool.fromEnvironment(
    'BIOMEDICA_FCM_ENABLED',
    defaultValue: false,
  );

  final CoreApiClient _api;
  final void Function(String messageId) onMessageReceived;
  final void Function() onNotificationOpened;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<void>? _initialization;
  String? _registeredFid;
  bool _unregistering = false;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('Permiso de notificaciones push denegado.');
      return;
    }

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) {
        final messageId = message.data['messageId'];
        if (messageId is String && messageId.isNotEmpty) {
          onMessageReceived(messageId);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Error al recibir una notificación push: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => onNotificationOpened(),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('No se pudo abrir el chat desde la notificación: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    final firstRegistration = Completer<String>();
    _tokenSubscription = messaging.onRegistered.listen(
      (installationId) {
        if (!firstRegistration.isCompleted) {
          firstRegistration.complete(installationId);
          return;
        }
        unawaited(
          _registerFid(installationId).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint(
              'No se pudo registrar el nuevo token de notificaciones: $error',
            );
            debugPrintStack(stackTrace: stackTrace);
          }),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!firstRegistration.isCompleted) {
          firstRegistration.completeError(error, stackTrace);
        }
        debugPrint('No se pudo registrar el token de notificaciones: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    await messaging.register();
    final installationId = await firstRegistration.future.timeout(
      const Duration(seconds: 20),
    );
    await _registerFid(installationId);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) onNotificationOpened();
  }

  Future<void> unregister() async {
    if (!enabled || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _unregistering = true;
    try {
      await _initialization;
    } catch (error, stackTrace) {
      debugPrint(
        'La inicialización push terminó con error al cerrar sesión: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
    await _tokenSubscription?.cancel();
    if (Firebase.apps.isEmpty) return;
    final fid = _registeredFid;
    if (fid == null || fid.isEmpty) return;
    try {
      await _api.request('DELETE', '/api/chat/push-token', body: {'fid': fid});
    } finally {
      _registeredFid = null;
      await FirebaseMessaging.instance.unregister();
    }
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }

  Future<void> _registerFid(String fid) async {
    if (_unregistering) return;
    final previousFid = _registeredFid;
    _registeredFid = fid;
    if (previousFid != null && previousFid != fid) {
      await _api.request(
        'DELETE',
        '/api/chat/push-token',
        body: {'fid': previousFid},
      );
    }
    await _api.put('/api/chat/push-token', {'fid': fid, 'platform': 'android'});
  }
}
