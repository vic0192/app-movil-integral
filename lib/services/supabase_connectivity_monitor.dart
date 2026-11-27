import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SupabaseConnectivityMonitor {
  SupabaseConnectivityMonitor({
    required String supabaseUrl,
    required this.publishableKey,
    this.interval = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 10),
    this.onResult,
    http.Client? client,
  }) : _healthUri = Uri.parse(
         '${supabaseUrl.replaceFirst(RegExp(r'/+$'), '')}/auth/v1/health',
       ),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (interval.inMicroseconds <= 0) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive.');
    }
    if (timeout.inMicroseconds <= 0) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final String publishableKey;
  final Duration interval;
  final Duration timeout;
  final ValueChanged<SupabaseConnectivityResult>? onResult;
  final Uri _healthUri;
  final http.Client _client;
  final bool _ownsClient;

  Timer? _timer;
  Future<SupabaseConnectivityResult>? _inFlight;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_disposed) throw StateError('The connectivity monitor is disposed.');
    if (_started) return;
    _started = true;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<SupabaseConnectivityResult> checkNow() async {
    if (_disposed) throw StateError('The connectivity monitor is disposed.');
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final check = _performCheck();
    _inFlight = check;
    try {
      return await check;
    } finally {
      if (identical(_inFlight, check)) _inFlight = null;
    }
  }

  Future<SupabaseConnectivityResult> _performCheck() async {
    final stopwatch = Stopwatch()..start();
    int? statusCode;
    String? error;
    try {
      final response = await _client
          .get(
            _healthUri,
            headers: {'apikey': publishableKey, 'Accept': 'application/json'},
          )
          .timeout(timeout);
      statusCode = response.statusCode;
    } on TimeoutException {
      error = 'timeout';
    } on http.ClientException catch (exception) {
      error = exception.message;
    } finally {
      stopwatch.stop();
    }

    final result = SupabaseConnectivityResult(
      statusCode: statusCode,
      elapsed: stopwatch.elapsed,
      error: error,
    );
    onResult?.call(result);
    return result;
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}

@immutable
class SupabaseConnectivityResult {
  const SupabaseConnectivityResult({
    required this.statusCode,
    required this.elapsed,
    required this.error,
  });

  final int? statusCode;
  final Duration elapsed;
  final String? error;

  bool get isHealthy =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;

  @override
  String toString() {
    final outcome = isHealthy
        ? 'HTTP $statusCode'
        : error ?? 'HTTP $statusCode';
    return '$outcome in ${elapsed.inMilliseconds} ms';
  }
}
