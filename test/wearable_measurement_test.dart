import 'package:biomedica_app/data/relational_measurement_repository.dart';
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
  }) => WearableMeasurementDraft(
    readingAt: readingAt ?? now,
    source: source,
    deviceName: 'Galaxy Watch',
    heartRateBpm: heartRateBpm,
    oxygenSaturationPercent: oxygenSaturationPercent,
    bodyTemperatureCelsius: bodyTemperatureCelsius,
  );

  group('WearableMeasurementDraft validation', () {
    test('accepts a current sensor heart-rate reading', () {
      expect(draft().validate(now: now), isNull);
    });

    test('serializes database fields using PostgreSQL column names', () {
      final serialized = draft(
        oxygenSaturationPercent: 97,
        bodyTemperatureCelsius: 36.7,
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
        ]),
      );
      expect(serialized['reading_at'], now.toIso8601String());
      expect(serialized['heart_rate_bpm'], 72);
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

    test('rejects stale and future readings', () {
      expect(
        draft(
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
