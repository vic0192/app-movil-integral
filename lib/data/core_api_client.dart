import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CoreApiClient {
  static const defaultBaseUrl = 'https://app-biomedica-web.onrender.com';

  CoreApiClient({
    http.Client? client,
    SessionTokenStore? tokenStore,
    this.accessTokenProvider,
    this.accessTokenRefresher,
    this.requestTimeout = const Duration(seconds: 15),
    String baseUrl = const String.fromEnvironment(
      'BIOMEDICA_CORE_API_URL',
      defaultValue: defaultBaseUrl,
    ),
  }) : _client = client ?? http.Client(),
       _tokenStore = tokenStore ?? const SecureSessionTokenStore(),
       _baseUrl = (baseUrl.isEmpty && kIsWeb ? Uri.base.origin : baseUrl)
           .replaceFirst(RegExp(r'/+$'), '');

  static final CoreApiClient instance = CoreApiClient();

  final http.Client _client;
  final SessionTokenStore _tokenStore;
  final Future<String?> Function()? accessTokenProvider;
  final Future<String?> Function()? accessTokenRefresher;
  final Duration requestTimeout;
  final String _baseUrl;

  Future<String?> readToken() => _tokenStore.readToken();

  Future<void> saveToken(String token) => _tokenStore.saveToken(token);

  Future<void> clearToken() => _tokenStore.clearToken();

  Future<Map<String, dynamic>> get(String path) => request('GET', path);

  Stream<Map<String, dynamic>> events(
    String path, {
    Duration reconnectDelay = const Duration(seconds: 3),
  }) {
    late final StreamController<Map<String, dynamic>> controller;
    Timer? reconnectTimer;
    StreamSubscription<String>? responseSubscription;
    var closed = false;
    var connecting = false;
    late void Function() scheduleReconnect;
    late Future<void> Function() connect;

    scheduleReconnect = () {
      if (closed || reconnectTimer != null) return;
      reconnectTimer = Timer(reconnectDelay, () {
        reconnectTimer = null;
        unawaited(connect());
      });
    };

    void reportError(Object error, [StackTrace? stackTrace]) {
      if (closed) return;
      controller.addError(error, stackTrace);
      if (error is! CoreApiException ||
          (error.statusCode != 401 && error.statusCode != 403)) {
        scheduleReconnect();
      }
    }

    connect = () async {
      if (closed || connecting) return;
      connecting = true;
      try {
        if (_baseUrl.isEmpty) {
          throw const CoreApiException(
            'La API de BioMedica no está configurada.',
          );
        }
        final token = await (accessTokenProvider?.call() ?? readToken());
        if (token == null || token.isEmpty) {
          throw const CoreApiException(
            'No hay una sesión activa para acceder a la API de BioMedica.',
            statusCode: 401,
          );
        }

        Future<http.StreamedResponse> send(String bearerToken) {
          final request = http.Request('GET', Uri.parse('$_baseUrl$path'))
            ..headers.addAll({
              'Accept': 'text/event-stream',
              'Authorization': 'Bearer $bearerToken',
              'Cache-Control': 'no-cache',
            });
          return _client.send(request).timeout(requestTimeout);
        }

        var response = await send(token);
        if (response.statusCode == 401 && accessTokenRefresher != null) {
          await response.stream.drain<void>();
          final refreshedToken = await accessTokenRefresher!();
          if (refreshedToken != null &&
              refreshedToken.isNotEmpty &&
              refreshedToken != token) {
            response = await send(refreshedToken);
          } else {
            throw const CoreApiException(
              'La sesión de Supabase venció. Inicia sesión nuevamente.',
              statusCode: 401,
            );
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorResponse = await http.Response.fromStream(response);
          throw _streamResponseError(errorResponse);
        }

        var buffer = '';
        responseSubscription = response.stream
            .transform(utf8.decoder)
            .listen(
              (chunk) {
                try {
                  buffer += chunk;
                  final lines = buffer.split('\n');
                  buffer = lines.removeLast();
                  for (final rawLine in lines) {
                    final line = rawLine.endsWith('\r')
                        ? rawLine.substring(0, rawLine.length - 1)
                        : rawLine;
                    if (!line.startsWith('data:')) continue;
                    final value = jsonDecode(line.substring(5).trimLeft());
                    if (value is! Map) {
                      throw const FormatException(
                        'La API envió un evento de reportes inválido.',
                      );
                    }
                    final event = Map<String, dynamic>.from(value);
                    final message = event['error'];
                    if (message is String) {
                      throw CoreApiException(message);
                    }
                    if (!closed) controller.add(event);
                  }
                } catch (error, stackTrace) {
                  reportError(error, stackTrace);
                  unawaited(responseSubscription?.cancel());
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                reportError(error, stackTrace);
              },
              onDone: scheduleReconnect,
              cancelOnError: true,
            );
      } on TimeoutException {
        reportError(
          const CoreApiException('La API tardó demasiado en responder.'),
        );
      } on http.ClientException catch (error) {
        reportError(
          CoreApiException('No se pudo conectar con la API: ${error.message}'),
        );
      } catch (error, stackTrace) {
        reportError(error, stackTrace);
      } finally {
        connecting = false;
      }
    };

    void onCancel() {
      closed = true;
      reconnectTimer?.cancel();
      unawaited(responseSubscription?.cancel());
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(connect()),
      onCancel: onCancel,
    );
    return controller.stream;
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, Object?> body = const {},
  ]) => request('POST', path, body: body);

  Future<Map<String, dynamic>> put(
    String path, [
    Map<String, Object?> body = const {},
  ]) => request('PUT', path, body: body);

  Future<Map<String, dynamic>> patch(
    String path, [
    Map<String, Object?> body = const {},
  ]) => request('PATCH', path, body: body);

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const CoreApiException(
        'La API de BioMedica no está configurada. Define '
        'BIOMEDICA_CORE_API_URL con la URL del servicio de Render.',
      );
    }
    final uri = Uri.parse('$_baseUrl$path');
    final token = authenticated
        ? await (accessTokenProvider?.call() ?? readToken())
        : null;
    if (authenticated &&
        accessTokenProvider != null &&
        (token == null || token.isEmpty)) {
      throw const CoreApiException(
        'No hay una sesión activa para acceder a la API de BioMedica.',
        statusCode: 401,
      );
    }
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';

    late http.Response response;
    try {
      response = await _send(method, uri, headers, body);
      if (authenticated &&
          response.statusCode == 401 &&
          accessTokenRefresher != null) {
        final refreshedToken = await accessTokenRefresher!();
        if (refreshedToken != null &&
            refreshedToken.isNotEmpty &&
            refreshedToken != token) {
          final retryHeaders = Map<String, String>.from(headers)
            ..['Authorization'] = 'Bearer $refreshedToken';
          response = await _send(method, uri, retryHeaders, body);
        }
      }
    } on TimeoutException {
      throw const CoreApiException(
        'La API tardó demasiado en responder. Inténtalo nuevamente.',
      );
    } on http.ClientException catch (error) {
      throw CoreApiException(
        'No se pudo conectar con la API: ${error.message}',
      );
    } on CoreApiException {
      rethrow;
    }

    Map<String, dynamic> decoded = const {};
    if (response.body.isNotEmpty) {
      final value = jsonDecode(response.body);
      if (value is! Map) {
        throw const CoreApiException('La API devolvió una respuesta inválida.');
      }
      decoded = Map<String, dynamic>.from(value);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CoreApiException(
        decoded['message'] as String? ??
            'La API respondió con el código ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, Object?>? body,
  ) async {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(requestTimeout);
  }

  CoreApiException _streamResponseError(http.Response response) {
    String? message;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } on FormatException {
      message = null;
    }
    return CoreApiException(
      message ?? 'La API respondió con el código ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }

  Stream<T> poll<T>(
    Future<T> Function() fetch, {
    Duration interval = const Duration(seconds: 15),
  }) {
    late final StreamController<T> controller;
    Timer? timer;
    var fetching = false;

    Future<void> load() async {
      if (fetching || controller.isClosed) return;
      fetching = true;
      try {
        controller.add(await fetch());
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        fetching = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(load());
        timer = Timer.periodic(interval, (_) => unawaited(load()));
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }
}

abstract interface class SessionTokenStore {
  Future<String?> readToken();

  Future<void> saveToken(String token);

  Future<void> clearToken();
}

class SecureSessionTokenStore implements SessionTokenStore {
  const SecureSessionTokenStore() : _storage = const FlutterSecureStorage();

  static const _tokenKey = 'biomedica_api_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}

class CoreApiException implements Exception {
  const CoreApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
