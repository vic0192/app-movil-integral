import 'package:biomedica_app/data/health_connect_repository.dart';
import 'package:biomedica_app/models/health_connect_record.dart';
import 'package:biomedica_app/services/health_connect_service.dart';
import 'package:biomedica_app/widgets/health_connect_home_summary.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeHealthConnectRecords', () {
    test('selects the latest record and orders each trend chronologically', () {
      final records = [
        _record(
          type: 'HEART_RATE',
          label: 'Frecuencia cardiaca',
          value: 72,
          recordedAt: DateTime.utc(2026, 11, 24, 12),
        ),
        _record(
          type: 'BLOOD_OXYGEN',
          label: 'Oxígeno en sangre (SpO₂)',
          value: 98,
          recordedAt: DateTime.utc(2026, 11, 24, 11),
        ),
        _record(
          type: 'HEART_RATE',
          label: 'Frecuencia cardiaca',
          value: 65,
          recordedAt: DateTime.utc(2026, 11, 24, 10),
        ),
      ];

      final summaries = summarizeHealthConnectRecords(records);

      expect(summaries, hasLength(2));
      expect(summaries.first.latest.dataType, 'HEART_RATE');
      expect(summaries.first.latest.value, 72);
      expect(summaries.first.history.map((record) => record.value), [65, 72]);
      expect(summaries.last.latest.dataType, 'BLOOD_OXYGEN');
    });

    test('formats body temperature in Celsius', () {
      final record = _record(
        type: 'BODY_TEMPERATURE',
        label: 'Temperatura corporal',
        value: 36.7,
        recordedAt: DateTime.utc(2026, 11, 24, 12),
      );

      expect(record.displayValue, '36.7 °C');
    });

    test(
      'shows available heart rate without inventing a missing temperature',
      () {
        final summaries = summarizeHealthConnectRecords([
          _record(
            type: 'HEART_RATE',
            label: 'Frecuencia cardiaca',
            value: 72,
            recordedAt: DateTime.utc(2026, 11, 24, 12),
          ),
        ]);

        expect(summaries.map((summary) => summary.latest.dataType), [
          'HEART_RATE',
        ]);
      },
    );
  });

  testWidgets('automatically saves only records with existing permissions', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final record = _record(
        type: 'HEART_RATE',
        label: 'Frecuencia cardiaca',
        value: 72,
        recordedAt: DateTime.utc(2026, 11, 24, 12),
      );
      final repository = _FakeHealthConnectRepository([record]);
      final service = _FakeHealthConnectService([record]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthConnectHomeSummary(
              repository: repository,
              healthService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.readCount, 1);
      expect(service.lastRequestedMissingPermissions, isFalse);
      expect(repository.savedRecords, [record]);
      expect(find.text('Frecuencia cardiaca'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('keeps saved readings visible when automatic sync is unavailable', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final record = _record(
        type: 'HEART_RATE',
        label: 'Frecuencia cardiaca',
        value: 72,
        recordedAt: DateTime.utc(2026, 11, 24, 12),
      );
      final repository = _FakeHealthConnectRepository([record]);
      final service = _FakeHealthConnectService(
        [record],
        error: StateError('Health Connect no disponible'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthConnectHomeSummary(
              repository: repository,
              healthService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Frecuencia cardiaca'), findsOneWidget);
      expect(
        find.textContaining('No se pudieron sincronizar datos nuevos'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

HealthConnectRecord _record({
  required String type,
  required String label,
  required double value,
  required DateTime recordedAt,
}) => HealthConnectRecord(
  externalId: '$type-${recordedAt.toIso8601String()}',
  dataType: type,
  label: label,
  value: value,
  unit: 'unit',
  recordedAt: recordedAt,
  endedAt: recordedAt,
  sourceName: 'Samsung Health',
  sourceId: 'com.samsung.android.health',
);

class _FakeHealthConnectRepository extends HealthConnectRepository {
  _FakeHealthConnectRepository(this.records);

  final List<HealthConnectRecord> records;
  List<HealthConnectRecord> savedRecords = const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> saveRecords(List<HealthConnectRecord> records) async {
    savedRecords = records;
  }

  @override
  Future<List<HealthConnectRecord>> loadRecentRecords({
    int limit = 200,
  }) async => records;
}

class _FakeHealthConnectService extends HealthConnectService {
  _FakeHealthConnectService(this.records, {this.error});

  final List<HealthConnectRecord> records;
  final Object? error;
  bool? lastRequestedMissingPermissions;
  int readCount = 0;

  @override
  Future<HealthConnectSyncResult> readRecentData({
    bool requestMissingPermissions = true,
  }) async {
    readCount++;
    lastRequestedMissingPermissions = requestMissingPermissions;
    if (error != null) throw error!;
    return HealthConnectSyncResult(authorizedTypes: 1, records: records);
  }
}
