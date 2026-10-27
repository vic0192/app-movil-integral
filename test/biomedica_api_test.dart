import 'dart:async';
import 'dart:io';

import 'package:biomedica_app/data/biomedica_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetchStatus decodes the status response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestReceived = Completer<void>();
    server.listen((request) async {
      if (!requestReceived.isCompleted) requestReceived.complete();
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"lastTelemetry":{"heartRate":75},"telemetryHistory":[]}');
      await request.response.close();
    });

    try {
      final api = BioMedicaApi(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      final status = await api.fetchStatus();
      await requestReceived.future;

      expect(status['lastTelemetry'], {'heartRate': 75});
      expect(status['telemetryHistory'], isEmpty);
    } finally {
      await server.close(force: true);
    }
  });
}
