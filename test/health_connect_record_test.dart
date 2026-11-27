import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:biomedica_app/models/health_connect_record.dart';

void main() {
  group('HealthConnectRecord', () {
    test('maps a heart rate with source and stable external identity', () {
      final point = HealthDataPoint(
        uuid: 'point-123',
        value: NumericHealthValue(numericValue: 72),
        type: HealthDataType.HEART_RATE,
        unit: HealthDataUnit.BEATS_PER_MINUTE,
        dateFrom: DateTime.utc(2026, 2, 1, 10),
        dateTo: DateTime.utc(2026, 2, 1, 10, 1),
        sourcePlatform: HealthPlatformType.googleHealthConnect,
        sourceDeviceId: 'device-1',
        sourceId: 'com.samsung.android.health',
        sourceName: 'Samsung Health',
      );

      final record = HealthConnectRecord.fromHealthDataPoint(point);

      expect(
        record.externalId,
        'HEART_RATE:com.samsung.android.health:point-123',
      );
      expect(record.label, 'Frecuencia cardiaca');
      expect(record.value, 72);
      expect(record.displayValue, '72 lpm');
      expect(record.sourceName, 'Samsung Health');
      expect(
        record.toSupabaseMap('patient-1')['recorded_at'],
        '2026-02-01T10:00:00.000Z',
      );
    });

    test('uses the recorded interval for sleep session duration', () {
      final start = DateTime.utc(2026, 2, 1, 22);
      final end = DateTime.utc(2026, 2, 2, 6, 30);
      final point = HealthDataPoint(
        uuid: 'sleep-123',
        value: NumericHealthValue(numericValue: 0),
        type: HealthDataType.SLEEP_SESSION,
        unit: HealthDataUnit.MINUTE,
        dateFrom: start,
        dateTo: end,
        sourcePlatform: HealthPlatformType.googleHealthConnect,
        sourceDeviceId: 'device-1',
        sourceId: 'com.samsung.android.health',
        sourceName: 'Samsung Health',
      );

      final record = HealthConnectRecord.fromHealthDataPoint(point);

      expect(record.value, 510);
      expect(record.displayValue, '8 h 30 min');
    });
  });
}
