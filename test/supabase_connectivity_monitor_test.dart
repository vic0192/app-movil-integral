import 'dart:async';
import 'dart:io';

import 'package:biomedica_app/services/supabase_connectivity_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('checks Supabase immediately and every configured interval', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final firstResult = Completer<SupabaseConnectivityResult>();
    final secondResult = Completer<SupabaseConnectivityResult>();
    server.listen((request) async {
      requests.add(request);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"status":"ok"}');
      await request.response.close();
    });
    final client = http.Client();
    final monitor = SupabaseConnectivityMonitor(
      supabaseUrl: 'http://${server.address.address}:${server.port}/',
      publishableKey: 'test-publishable-key',
      client: client,
      interval: const Duration(milliseconds: 25),
      onResult: (result) {
        if (!firstResult.isCompleted) {
          firstResult.complete(result);
        } else if (!secondResult.isCompleted) {
          secondResult.complete(result);
        }
      },
    );
    addTearDown(() async {
      monitor.dispose();
      client.close();
      await server.close(force: true);
    });

    monitor.start();

    final result = await firstResult.future.timeout(const Duration(seconds: 2));
    expect(result.isHealthy, isTrue);
    expect(result.statusCode, HttpStatus.ok);
    expect(result.error, isNull);
    expect(result.toString(), startsWith('HTTP 200 in '));
    await secondResult.future.timeout(const Duration(seconds: 2));
    monitor.stop();

    expect(requests.length, greaterThanOrEqualTo(2));
    expect(requests.first.method, 'GET');
    expect(requests.first.uri.path, '/auth/v1/health');
    expect(requests.first.headers.value('apikey'), 'test-publishable-key');
  });

  test('reports a non-success status without treating it as healthy', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..write('unavailable');
      await request.response.close();
    });
    final client = http.Client();
    final monitor = SupabaseConnectivityMonitor(
      supabaseUrl: 'http://${server.address.address}:${server.port}',
      publishableKey: 'test-publishable-key',
      client: client,
    );
    addTearDown(() async {
      monitor.dispose();
      client.close();
      await server.close(force: true);
    });

    final result = await monitor.checkNow();

    expect(result.isHealthy, isFalse);
    expect(result.statusCode, HttpStatus.serviceUnavailable);
    expect(result.toString(), startsWith('HTTP 503 in '));
  });

  test('reports a client connection error', () async {
    final client = _FailingClient(http.ClientException('offline'));
    final monitor = SupabaseConnectivityMonitor(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'test-publishable-key',
      client: client,
    );
    addTearDown(() {
      monitor.dispose();
      client.close();
    });

    final result = await monitor.checkNow();

    expect(result.isHealthy, isFalse);
    expect(result.statusCode, isNull);
    expect(result.error, 'offline');
    expect(result.toString(), startsWith('offline in '));
  });

  test('reports a probe timeout', () async {
    final client = _HangingClient();
    final monitor = SupabaseConnectivityMonitor(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'test-publishable-key',
      client: client,
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      monitor.dispose();
      client.close();
    });

    final result = await monitor.checkNow();

    expect(result.isHealthy, isFalse);
    expect(result.statusCode, isNull);
    expect(result.error, 'timeout');
    expect(result.toString(), startsWith('timeout in '));
  });
}

class _FailingClient extends http.BaseClient {
  _FailingClient(this.error);

  final http.ClientException error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(error);
}

class _HangingClient extends http.BaseClient {
  final _response = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _response.future;
}
