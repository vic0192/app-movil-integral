import 'package:biomedica_app/models/wearable_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17, 18);

  Map<String, dynamic> capture({
    Object? heartRate = 76,
    Object? updatedAt,
    Object? source = 'wear_os_sensor',
    Object? deviceName = 'samsung SM-R890',
    Object? spo2,
    Object? temperature,
  }) => {
    'captureRequested': true,
    'captureId': 'capture-unit-1',
    'updatedAt': updatedAt ?? now.millisecondsSinceEpoch,
    'source': source,
    'deviceName': deviceName,
    'heartRate': ?heartRate,
    'spo2': ?spo2,
    'temperature': ?temperature,
  };

  test('accepts a current heart-rate capture from the watch', () {
    final draft = WearableMeasurementDraft.fromWatchReading(capture());

    expect(draft.heartRateBpm, 76);
    expect(draft.deviceName, 'samsung SM-R890');
    expect(draft.validate(now: now), isNull);
  });

  test('rejects a capture with a missing heart-rate value', () {
    expect(
      () => WearableMeasurementDraft.fromWatchReading(capture(heartRate: null)),
      throwsFormatException,
    );
  });

  test('rejects an empty device name', () {
    final draft = WearableMeasurementDraft.fromWatchReading(
      capture(deviceName: '   '),
    );

    expect(draft.validate(now: now), contains('dispositivo'));
  });

  test('rejects heart rate outside the accepted range', () {
    final draft = WearableMeasurementDraft.fromWatchReading(
      capture(heartRate: 221),
    );

    expect(draft.validate(now: now), contains('frecuencia'));
  });

  test('rejects optional saturation outside the accepted range', () {
    final draft = WearableMeasurementDraft.fromWatchReading(capture(spo2: 101));

    expect(draft.validate(now: now), contains('SpO₂'));
  });

  test('accepts a watch capture delayed by a temporary sync interruption', () {
    final draft = WearableMeasurementDraft.fromWatchReading(
      capture(
        updatedAt: now
            .subtract(const Duration(minutes: 6))
            .millisecondsSinceEpoch,
      ),
    );

    expect(draft.validate(now: now), isNull);
  });

  test('rejects a watch capture older than the pending-sync window', () {
    final draft = WearableMeasurementDraft.fromWatchReading(
      capture(
        updatedAt: now
            .subtract(const Duration(hours: 24, minutes: 1))
            .millisecondsSinceEpoch,
      ),
    );

    expect(draft.validate(now: now), contains('vencida'));
  });

  test('does not invent measurements that are not in the sensor payload', () {
    final draft = WearableMeasurementDraft.fromWatchReading(capture());

    expect(draft.oxygenSaturationPercent, isNull);
    expect(draft.bodyTemperatureCelsius, isNull);
  });
}
