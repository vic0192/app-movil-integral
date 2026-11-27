import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biomedica_app/data/core_api_client.dart';
import 'package:biomedica_app/data/relational_measurement_repository.dart';
import 'package:biomedica_app/models/wearable_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saved watch measurement is returned in the patient history stream',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final rows = <Map<String, dynamic>>[];
      var nextId = 1;
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
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          final row = <String, dynamic>{
            'id': 'measurement-${nextId++}',
            'ownerUid': 'patient-1',
            'readingAt': body['readingAt'],
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            ...body,
          };
          rows.add(row);
          request.response.write(jsonEncode({'measurement': row}));
        } else if (request.method == 'GET' &&
            request.uri.path == '/api/measurements') {
          request.response.write(jsonEncode({'measurements': rows}));
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
        heartRateBpm: 83,
      );
      final received = Completer<List<WearableMeasurement>>();
      StreamSubscription<List<WearableMeasurement>>? subscription;

      try {
        await repository.initialize();
        await repository.saveMeasurement(draft);
        subscription = repository.watchMeasurements().listen((measurements) {
          if (!received.isCompleted) received.complete(measurements);
        }, onError: received.completeError);

        final history = await received.future.timeout(
          const Duration(seconds: 2),
        );
        expect(history, hasLength(1));
        expect(history.single.heartRateBpm, 83);
        expect(history.single.ownerUid, 'patient-1');
        expect(history.single.deviceName, 'Galaxy Watch');
      } finally {
        await subscription?.cancel();
        await server.close(force: true);
      }
    },
  );
}
