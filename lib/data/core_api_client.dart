import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CoreApiClient {
  CoreApiClient({
    http.Client? client,
    SessionTokenStore? tokenStore,
    this.accessTokenProvider,
    String baseUrl = const String.fromEnvironment(
      'BIOMEDICA_CORE_API_URL',
      defaultValue: '',
    ),
  }) : _client = client ?? http.Client(),
       _tokenStore = tokenStore ?? const SecureSessionTokenStore(),
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  static final CoreApiClient instance = CoreApiClient();

  final http.Client _client;
  final SessionTokenStore _tokenStore;
  final Future<String?> Function()? accessTokenProvider;
  final String _baseUrl;

  Future<String?> readToken() => _tokenStore.readToken();

  Future<void> saveToken(String token) => _tokenStore.saveToken(token);

  Future<void> clearToken() => _tokenStore.clearToken();

  Future<Map<String, dynamic>> get(String path) => request('GET', path);

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

    late final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const CoreApiException(
        'La API tardó demasiado en responder. Inténtalo nuevamente.',
      );
    } on http.ClientException catch (error) {
      throw CoreApiException(
        'No se pudo conectar con la API: ${error.message}',
      );
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
