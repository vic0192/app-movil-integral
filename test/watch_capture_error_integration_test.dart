import 'dart:convert';
import 'dart:io';

import 'package:biomedica_app/data/core_api_client.dart';
import 'package:biomedica_app/data/relational_measurement_repository.dart';
import 'package:biomedica_app/models/wearable_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports an API write failure without returning a successful record id',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/api/auth/me') {
          request.response.write(
            jsonEncode({
              'user': {'role': 'patient'},
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path == '/api/measurements') {
          request.response
            ..statusCode = HttpStatus.serviceUnavailable
            ..write(
              jsonEncode({
                'message': 'Almacenamiento temporalmente no disponible.',
              }),
            );
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write(jsonEncode({'message': 'Ruta no encontrada.'}));
        }
        await request.response.close();
      });

      final repository = RelationalMeasurementRepository(
        api: CoreApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          accessTokenProvider: () async => 'patient-session-token',
        ),
      );
      final now = DateTime.now();
      final draft = WearableMeasurementDraft(
        readingAt: now,
        source: 'wear_os_sensor',
        deviceName: 'Galaxy Watch',
        heartRateBpm: 79,
      );

      try {
        await repository.initialize();
        await expectLater(
          repository.saveMeasurement(draft),
          throwsA(
            isA<MeasurementStoreException>().having(
              (error) => error.message,
              'message',
              contains('Almacenamiento temporalmente no disponible.'),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}
