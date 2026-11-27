import 'dart:convert';

import 'package:biomedica_app/data/relational_measurement_repository.dart';
import 'package:biomedica_app/ble/wear_os_data_layer.dart';
import 'package:biomedica_app/models/wearable_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);

  WearableMeasurementDraft draft({
    DateTime? readingAt,
    String source = 'wear_os_sensor',
    int heartRateBpm = 72,
    int? oxygenSaturationPercent,
    double? bodyTemperatureCelsius,
    Map<String, WearableSensorReadingRecord> sensorReadings = const {},
  }) => WearableMeasurementDraft(
    readingAt: readingAt ?? now,
    source: source,
    deviceName: 'Galaxy Watch',
    heartRateBpm: heartRateBpm,
    oxygenSaturationPercent: oxygenSaturationPercent,
    bodyTemperatureCelsius: bodyTemperatureCelsius,
    sensorReadings: sensorReadings,
  );

  group('WearableMeasurementDraft validation', () {
    test('parses an explicit watch capture with only measured values', () {
      final draft = WearableMeasurementDraft.fromWatchReading({
        'captureId': 'capture-1',
        'captureRequested': true,
        'updatedAt': now.millisecondsSinceEpoch,
        'source': 'wear_os_sensor',
        'deviceName': 'samsung SM-R890',
        'heartRate': 74,
      });

      expect(
        draft.readingAt.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      expect(draft.heartRateBpm, 74);
      expect(draft.oxygenSaturationPercent, isNull);
      expect(draft.bodyTemperatureCelsius, isNull);
      expect(draft.validate(now: now), isNull);
    });

    test('rejects incomplete watch capture payloads', () {
      expect(
        () => WearableMeasurementDraft.fromWatchReading({
          'updatedAt': now.millisecondsSinceEpoch,
          'source': 'wear_os_sensor',
          'deviceName': 'Galaxy Watch',
        }),
        throwsFormatException,
      );
    });

    test('accepts a current sensor heart-rate reading', () {
      expect(draft().validate(now: now), isNull);
    });

    test('serializes database fields using PostgreSQL column names', () {
      final serialized = draft(
        oxygenSaturationPercent: 97,
        bodyTemperatureCelsius: 36.7,
        sensorReadings: {
          'step_counter': const WearableSensorReadingRecord(
            label: 'Pasos acumulados',
            unit: 'pasos',
            values: [1250],
          ),
        },
      ).toSupabaseMap();

      expect(
        serialized.keys,
        containsAll([
          'reading_at',
          'source',
          'device_name',
          'heart_rate_bpm',
          'oxygen_saturation_percent',
          'body_temperature_celsius',
          'sensor_readings',
        ]),
      );
      expect(serialized['reading_at'], now.toIso8601String());
      expect(serialized['heart_rate_bpm'], 72);
      expect(serialized['sensor_readings'], {
        'step_counter': {
          'label': 'Pasos acumulados',
          'unit': 'pasos',
          'values': [1250],
        },
      });
    });

    test('parses watch sensor values and serializes them for Supabase', () {
      final draft = WearableMeasurementDraft.fromWatchReading({
        'updatedAt': now.millisecondsSinceEpoch,
        'source': 'wear_os_sensor',
        'deviceName': 'samsung SM-R890',
        'heartRate': 74,
        'sensorReadingsJson': jsonEncode({
          'step_counter': {
            'label': 'Pasos acumulados',
            'unit': 'pasos',
            'values': [1250],
            'observedAt': now.millisecondsSinceEpoch,
          },
          'accelerometer': {
            'label': 'Acelerómetro',
            'unit': 'm/s²',
            'values': [0.1, 0.2, 9.8],
            'observedAt': now.millisecondsSinceEpoch - 1000,
          },
        }),
      });

      expect(draft.sensorReadings, hasLength(2));
      expect(
        draft.sensorReadings['step_counter']?.observedAt,
        DateTime.fromMillisecondsSinceEpoch(
          now.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      expect(draft.toSupabaseMap()['sensor_readings'], {
        'step_counter': {
          'label': 'Pasos acumulados',
          'unit': 'pasos',
          'values': [1250],
          'observedAt': now.toIso8601String(),
        },
        'accelerometer': {
          'label': 'Acelerómetro',
          'unit': 'm/s²',
          'values': [0.1, 0.2, 9.8],
          'observedAt': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      });
    });

    test('parses all transmitted watch sensor values and their inventory', () {
      final readings = WearOsDataLayer.parseSensorReadings(
        jsonEncode({
          'heart_rate': {
            'label': 'Frecuencia cardiaca',
            'unit': 'BPM',
            'values': [74],
            'observedAt': now.millisecondsSinceEpoch,
          },
          'step_counter': {
            'label': 'Pasos acumulados',
            'unit': 'pasos',
            'values': [1250],
            'observedAt': now.millisecondsSinceEpoch,
          },
          'atmospheric_pressure': {
            'label': 'Presión atmosférica',
            'unit': 'hPa',
            'values': [1012.4],
            'observedAt': now.millisecondsSinceEpoch,
          },
        }),
      );
      final inventory = WearOsDataLayer.parseAvailableSensors(
        jsonEncode([
          {
            'key': 'heart_rate',
            'label': 'Frecuencia cardiaca',
            'unit': 'BPM',
            'permissionRequired': false,
            'collecting': true,
          },
          {
            'key': 'step_counter',
            'label': 'Pasos acumulados',
            'unit': 'pasos',
            'permissionRequired': true,
            'collecting': false,
          },
        ]),
      );

      expect(
        readings.keys,
        containsAll(['heart_rate', 'step_counter', 'atmospheric_pressure']),
      );
      expect(readings['step_counter']?.formattedValue, '1250');
      expect(readings['atmospheric_pressure']?.observedAt, now);
      expect(inventory.map((sensor) => sensor.key), [
        'heart_rate',
        'step_counter',
      ]);
      expect(inventory.first.isCollecting, isTrue);
      expect(inventory.last.permissionRequired, isTrue);
    });

    test('reads saved generic sensor values from a Supabase row', () {
      final measurement = WearableMeasurement.fromJson({
        'id': 'measurement-1',
        'owner_uid': 'patient-1',
        'reading_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'source': 'wear_os_sensor',
        'device_name': 'Galaxy Watch4 Classic',
        'heart_rate_bpm': 74,
        'sensor_readings': {
          'step_counter': {
            'label': 'Pasos acumulados',
            'unit': 'pasos',
            'values': [1250],
          },
        },
      });

      expect(measurement.sensorReadings['step_counter']?.values, [1250]);
    });

    test('accepts optional sensor fields when in capture ranges', () {
      expect(
        draft(
          oxygenSaturationPercent: 97,
          bodyTemperatureCelsius: 36.7,
        ).validate(now: now),
        isNull,
      );
    });

    test('rejects demo or unsupported sources', () {
      expect(
        draft(source: 'BioWatch Wear OS demo').validate(now: now),
        contains('fuente'),
      );
    });

    test('rejects implausible measurement values', () {
      expect(draft(heartRateBpm: 0).validate(now: now), contains('frecuencia'));
      expect(
        draft(oxygenSaturationPercent: 101).validate(now: now),
        contains('SpO₂'),
      );
      expect(
        draft(bodyTemperatureCelsius: double.nan).validate(now: now),
        contains('temperatura'),
      );
    });

    test('keeps BLE readings fresh and rejects future readings', () {
      expect(
        draft(
          source: 'ble_hr',
          readingAt: now.subtract(const Duration(minutes: 6)),
        ).validate(now: now),
        contains('vencida'),
      );
      expect(
        draft(
          readingAt: now.add(const Duration(minutes: 3)),
        ).validate(now: now),
        contains('vencida'),
      );
    });

    test('accepts a delayed watch capture within its sync window', () {
      expect(
        draft(
          readingAt: now.subtract(const Duration(minutes: 6)),
        ).validate(now: now),
        isNull,
      );
    });
  });

  test('repository rejects invalid data before API access', () {
    expect(
      () => RelationalMeasurementRepository().saveMeasurement(
        draft(source: 'demo'),
      ),
      throwsA(isA<MeasurementStoreException>()),
    );
  });
}
