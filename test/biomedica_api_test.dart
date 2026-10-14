import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biomedica_app/data/biomedica_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pushTelemetry sends only supplied measurements to the API', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedBody = Completer<String>();
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      if (!receivedBody.isCompleted) receivedBody.complete(body);
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"ok":true}');
      await request.response.close();
    });

    try {
      final api = BioMedicaApi(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );
      await api.pushTelemetry(
        wearableId: 'stf-device',
        measurements: const {'heartRate': 76},
      );

      final payload =
          jsonDecode(await receivedBody.future) as Map<String, dynamic>;
      expect(payload['wearableId'], 'stf-device');
      expect(payload['source'], 'stf-kronos-blaze-ble');
      expect(payload['heartRate'], 76);
      expect(payload.containsKey('spo2'), isFalse);
      expect(payload.containsKey('temperature'), isFalse);
    } finally {
      await server.close(force: true);
    }
  });
}
