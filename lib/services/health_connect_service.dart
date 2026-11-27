import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../models/health_connect_record.dart';

class HealthConnectService {
  HealthConnectService({Health? health}) : _health = health ?? Health();

  static const _settingsChannel = MethodChannel('com.biomedica/health_connect');
  final Health _health;

  static const List<HealthDataType> _dataTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.LEAN_BODY_MASS,
    HealthDataType.BODY_MASS_INDEX,
    HealthDataType.BODY_WATER_MASS,
    HealthDataType.WEIGHT,
    HealthDataType.HEIGHT,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_OUT_OF_BED,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_UNKNOWN,
  ];

  Future<HealthConnectSdkStatus?> getStatus() async {
    if (!_isAndroid) return null;
    await _health.configure();
    return _health.getHealthConnectSdkStatus();
  }

  Future<void> installOrUpdateHealthConnect() => _health.installHealthConnect();

  Future<void> openSettings() async {
    if (!_isAndroid) {
      throw const HealthConnectUnavailableException(
        'La configuración de Health Connect está disponible en Android.',
      );
    }
    await _settingsChannel.invokeMethod<void>('openSettings');
  }

  Future<HealthConnectSyncResult> readRecentData({
    bool requestMissingPermissions = true,
  }) async {
    if (!_isAndroid) {
      throw const HealthConnectUnavailableException(
        'La sincronización con Health Connect está disponible en Android.',
      );
    }
    await _health.configure();
    final status = await _health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) {
      throw const HealthConnectUnavailableException(
        'Health Connect no está disponible. Instálalo o actualízalo e inténtalo de nuevo.',
      );
    }

    final missingTypes = <HealthDataType>[];
    for (final type in _dataTypes) {
      final hasPermission = await _health.hasPermissions(
        [type],
        permissions: const [HealthDataAccess.READ],
      );
      if (hasPermission != true) missingTypes.add(type);
    }

    if (missingTypes.isNotEmpty && requestMissingPermissions) {
      await _health.requestAuthorization(
        missingTypes,
        permissions: List<HealthDataAccess>.filled(
          missingTypes.length,
          HealthDataAccess.READ,
        ),
      );
    }

    final readableTypes = <HealthDataType>[];
    for (final type in _dataTypes) {
      final hasPermission = await _health.hasPermissions(
        [type],
        permissions: const [HealthDataAccess.READ],
      );
      if (hasPermission == true) readableTypes.add(type);
    }

    if (readableTypes.isEmpty) {
      return const HealthConnectSyncResult(authorizedTypes: 0, records: []);
    }

    final endTime = DateTime.now();
    final points = await _health.getHealthDataFromTypes(
      types: readableTypes,
      startTime: endTime.subtract(const Duration(days: 7)),
      endTime: endTime,
    );
    return HealthConnectSyncResult(
      authorizedTypes: readableTypes.length,
      records: points
          .map(HealthConnectRecord.fromHealthDataPoint)
          .toList(growable: false),
    );
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

class HealthConnectSyncResult {
  const HealthConnectSyncResult({
    required this.authorizedTypes,
    required this.records,
  });

  final int authorizedTypes;
  final List<HealthConnectRecord> records;
}

class HealthConnectUnavailableException implements Exception {
  const HealthConnectUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
