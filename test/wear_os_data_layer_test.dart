import 'dart:convert';

import 'package:biomedica_app/ble/wear_os_data_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses sensor values and preserves their units', () {
    final readings = WearOsDataLayer.parseSensorReadings(
      jsonEncode({
        'heart_rate': {
          'label': 'Frecuencia cardiaca',
          'unit': 'BPM',
          'values': [82],
        },
        'accelerometer': {
          'label': 'Acelerómetro',
          'unit': 'm/s²',
          'values': [0.1, 0.2, 9.8],
        },
      }),
    );

    expect(readings['heart_rate']?.formattedValue, '82');
    expect(readings['heart_rate']?.unit, 'BPM');
    expect(readings['accelerometer']?.values, [0.1, 0.2, 9.8]);
  });

  test('parses available sensors and identifies missing permissions', () {
    final sensors = WearOsDataLayer.parseAvailableSensors(
      jsonEncode([
        {
          'key': 'step_counter',
          'label': 'Pasos acumulados',
          'unit': 'pasos',
          'permissionRequired': true,
        },
      ]),
    );

    expect(sensors, hasLength(1));
    expect(sensors.single.key, 'step_counter');
    expect(sensors.single.permissionRequired, isTrue);
  });

  test('parses a connected Wear OS node by advertised device name', () {
    final node = WearOsNode.fromMap({
      'id': 'watch-node',
      'displayName': 'Galaxy Watch4 Classic',
      'isNearby': true,
    });

    expect(node.displayName, 'Galaxy Watch4 Classic');
    expect(node.isNearby, isTrue);
  });

  test('rejects malformed sensor data rather than fabricating a reading', () {
    expect(
      () => WearOsDataLayer.parseSensorReadings('{"heart_rate":{}}'),
      throwsFormatException,
    );
  });
}
