import 'package:health/health.dart';

class HealthConnectRecord {
  const HealthConnectRecord({
    required this.externalId,
    required this.dataType,
    required this.label,
    required this.value,
    required this.unit,
    required this.recordedAt,
    required this.endedAt,
    required this.sourceName,
    required this.sourceId,
  });

  final String externalId;
  final String dataType;
  final String label;
  final double value;
  final String unit;
  final DateTime recordedAt;
  final DateTime endedAt;
  final String sourceName;
  final String sourceId;

  factory HealthConnectRecord.fromHealthDataPoint(HealthDataPoint point) {
    final value = _numericValue(point);
    final sourceId = point.sourceId.isEmpty ? 'unknown' : point.sourceId;
    final fallbackId = [
      point.dateFrom.toUtc().toIso8601String(),
      point.dateTo.toUtc().toIso8601String(),
      value.toString(),
    ].join('|');
    final pointId = point.uuid.isEmpty ? fallbackId : point.uuid;

    return HealthConnectRecord(
      externalId: '${point.type.name}:$sourceId:$pointId',
      dataType: point.type.name,
      label: _labelFor(point.type),
      value: value,
      unit: point.unit.name,
      recordedAt: point.dateFrom,
      endedAt: point.dateTo,
      sourceName: point.sourceName,
      sourceId: sourceId,
    );
  }

  factory HealthConnectRecord.fromJson(Map<String, dynamic> json) =>
      HealthConnectRecord(
        externalId: json['external_id'] as String,
        dataType: json['data_type'] as String,
        label: json['label'] as String,
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        endedAt: DateTime.parse(json['ended_at'] as String),
        sourceName: json['source_name'] as String? ?? '',
        sourceId: json['source_id'] as String? ?? '',
      );

  Map<String, dynamic> toSupabaseMap(String ownerUid) => {
    'owner_uid': ownerUid,
    'external_id': externalId,
    'data_type': dataType,
    'label': label,
    'value': value,
    'unit': unit,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'source_name': sourceName,
    'source_id': sourceId,
  };

  String get displayValue {
    if (dataType.startsWith('SLEEP_')) {
      final totalMinutes = value.round();
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours == 0) return '$minutes min';
      if (minutes == 0) return '$hours h';
      return '$hours h $minutes min';
    }

    final formatted = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$formatted $_unitLabel';
  }

  String get _unitLabel => switch (dataType) {
    'HEART_RATE' || 'RESTING_HEART_RATE' => 'lpm',
    'BLOOD_OXYGEN' || 'BODY_FAT_PERCENTAGE' => '%',
    'BODY_TEMPERATURE' => '°C',
    'BLOOD_PRESSURE_SYSTOLIC' || 'BLOOD_PRESSURE_DIASTOLIC' => 'mmHg',
    'BODY_MASS_INDEX' => 'IMC',
    'WEIGHT' || 'LEAN_BODY_MASS' || 'BODY_WATER_MASS' => 'kg',
    'HEIGHT' => 'm',
    _ => unit,
  };

  static double _numericValue(HealthDataPoint point) {
    if (point.type.name.startsWith('SLEEP_')) {
      return point.dateTo.difference(point.dateFrom).inSeconds / 60;
    }
    final healthValue = point.value;
    if (healthValue is! NumericHealthValue) {
      throw FormatException(
        'El tipo ${point.type.name} no contiene un valor numérico compatible.',
      );
    }
    final value = healthValue.numericValue;
    if (!value.isFinite) {
      throw FormatException('Health Connect devolvió un valor no finito.');
    }
    return value.toDouble();
  }

  static String _labelFor(HealthDataType type) => switch (type) {
    HealthDataType.HEART_RATE => 'Frecuencia cardiaca',
    HealthDataType.RESTING_HEART_RATE => 'Frecuencia cardiaca en reposo',
    HealthDataType.BLOOD_OXYGEN => 'Oxígeno en sangre (SpO₂)',
    HealthDataType.BODY_TEMPERATURE => 'Temperatura corporal',
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC => 'Presión arterial sistólica',
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC => 'Presión arterial diastólica',
    HealthDataType.BODY_FAT_PERCENTAGE => 'Grasa corporal',
    HealthDataType.LEAN_BODY_MASS => 'Masa magra',
    HealthDataType.BODY_MASS_INDEX => 'Índice de masa corporal',
    HealthDataType.BODY_WATER_MASS => 'Agua corporal',
    HealthDataType.WEIGHT => 'Peso',
    HealthDataType.HEIGHT => 'Estatura',
    HealthDataType.SLEEP_SESSION => 'Sesión de sueño',
    HealthDataType.SLEEP_ASLEEP => 'Tiempo dormido',
    HealthDataType.SLEEP_AWAKE => 'Despierto durante el sueño',
    HealthDataType.SLEEP_AWAKE_IN_BED => 'Despierto en cama',
    HealthDataType.SLEEP_DEEP => 'Sueño profundo',
    HealthDataType.SLEEP_LIGHT => 'Sueño ligero',
    HealthDataType.SLEEP_OUT_OF_BED => 'Fuera de cama',
    HealthDataType.SLEEP_REM => 'Sueño REM',
    HealthDataType.SLEEP_UNKNOWN => 'Sueño sin clasificar',
    _ => type.name,
  };
}

class SharedHealthConnectRecord {
  const SharedHealthConnectRecord({
    required this.patientUid,
    required this.patientName,
    required this.record,
  });

  final String patientUid;
  final String patientName;
  final HealthConnectRecord record;
}
