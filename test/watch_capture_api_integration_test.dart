import 'dart:convert';
import 'dart:io';

import 'package:biomedica_app/data/core_api_client.dart';
import 'package:biomedica_app/data/relational_measurement_repository.dart';
import 'package:biomedica_app/models/wearable_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late RelationalMeasurementRepository repository;
  late Map<String, dynamic>? savedBody;
  late List<String?> authorizations;
  late String accessToken;

  setUp(() async {
    savedBody = null;
    authorizations = [];
    accessToken = 'patient-session-token';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/api/auth/me') {
        if (request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer patient-session-token') {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(jsonEncode({'message': 'La sesión no es válida.'}));
        } else {
          request.response.write(
            jsonEncode({
              'user': {'role': 'patient'},
            }),
          );
        }
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/measurements') {
        savedBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.write(
          jsonEncode({
            'measurement': {'id': 'measurement-101'},
          }),
        );
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write(jsonEncode({'message': 'Ruta no encontrada.'}));
      }
      await request.response.close();
    });

    final api = CoreApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}',
      accessTokenProvider: () async => accessToken,
    );
    repository = RelationalMeasurementRepository(api: api);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'watch capture is authenticated and persisted by the measurement API',
    () async {
      final now = DateTime.now();
      final draft = WearableMeasurementDraft.fromWatchReading({
        'captureId': 'capture-integration-101',
        'captureRequested': true,
        'updatedAt': now.millisecondsSinceEpoch,
        'source': 'wear_os_sensor',
        'deviceName': 'samsung SM-R890',
        'heartRate': 81,
      });

      await repository.initialize();
      final id = await repository.saveMeasurement(draft);

      expect(id, 'measurement-101');
      expect(savedBody, isNotNull);
      expect(savedBody!['heartRateBpm'], 81);
      expect(savedBody!['source'], 'wear_os_sensor');
      expect(savedBody!['deviceName'], 'samsung SM-R890');
      expect(savedBody!['oxygenSaturationPercent'], isNull);
      expect(authorizations, everyElement('Bearer patient-session-token'));
      expect(authorizations, hasLength(2));
    },
  );

  test(
    'rejects an unsupported watch record before sending a write request',
    () async {
      final now = DateTime.now();
      final draft = WearableMeasurementDraft(
        readingAt: now,
        source: 'demo',
        deviceName: 'Galaxy Watch',
        heartRateBpm: 75,
      );

      await repository.initialize();
      await expectLater(
        repository.saveMeasurement(draft),
        throwsA(isA<MeasurementStoreException>()),
      );

      expect(savedBody, isNull);
      expect(authorizations, hasLength(1));
    },
  );

  test(
    'rejects an expired session before a watch record can be persisted',
    () async {
      accessToken = 'expired-session-token';

      await expectLater(
        repository.initialize(),
        throwsA(
          isA<MeasurementStoreException>().having(
            (error) => error.message,
            'message',
            contains('La sesión no es válida.'),
          ),
        ),
      );

      expect(savedBody, isNull);
      expect(authorizations, ['Bearer expired-session-token']);
    },
  );
}
