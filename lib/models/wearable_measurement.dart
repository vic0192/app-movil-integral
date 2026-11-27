import 'dart:convert';

const wearOsCaptureMaxAge = Duration(hours: 24);

class WearableMeasurementDraft {
  const WearableMeasurementDraft({
    required this.readingAt,
    required this.source,
    required this.deviceName,
    required this.heartRateBpm,
    this.oxygenSaturationPercent,
    this.bodyTemperatureCelsius,
    this.sensorReadings = const {},
  });

  final DateTime readingAt;
  final String source;
  final String deviceName;
  final int heartRateBpm;
  final int? oxygenSaturationPercent;
  final double? bodyTemperatureCelsius;
  final Map<String, WearableSensorReadingRecord> sensorReadings;

  factory WearableMeasurementDraft.fromWatchReading(
    Map<String, dynamic> reading,
  ) {
    final updatedAt = reading['updatedAt'];
    final source = reading['source'];
    final deviceName = reading['deviceName'];
    final heartRate = reading['heartRate'];
    if (updatedAt is! num ||
        source is! String ||
        deviceName is! String ||
        heartRate is! num) {
      throw const FormatException('El reloj envió una medición incompleta.');
    }

    final oxygenSaturation = reading['spo2'];
    final temperature = reading['temperature'];
    final sensorReadings =
        reading['sensorReadings'] ?? reading['sensorReadingsJson'];
    return WearableMeasurementDraft(
      readingAt: DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt()),
      source: source,
      deviceName: deviceName,
      heartRateBpm: heartRate.round(),
      oxygenSaturationPercent: oxygenSaturation is num
          ? oxygenSaturation.round()
          : null,
      bodyTemperatureCelsius: temperature is num
          ? temperature.toDouble()
          : null,
      sensorReadings: _parseSensorReadings(sensorReadings),
    );
  }

  Map<String, Object?> toJson() => {
    'readingAt': readingAt.toUtc().toIso8601String(),
    'source': source,
    'deviceName': deviceName.trim(),
    'heartRateBpm': heartRateBpm,
    'oxygenSaturationPercent': oxygenSaturationPercent,
    'bodyTemperatureCelsius': bodyTemperatureCelsius,
    'sensorReadings': _sensorReadingsToJson(sensorReadings),
  };

  Map<String, Object?> toSupabaseMap() => {
    'reading_at': readingAt.toUtc().toIso8601String(),
    'source': source,
    'device_name': deviceName.trim(),
    'heart_rate_bpm': heartRateBpm,
    'oxygen_saturation_percent': oxygenSaturationPercent,
    'body_temperature_celsius': bodyTemperatureCelsius,
    'sensor_readings': _sensorReadingsToJson(sensorReadings),
  };

  String? validate({DateTime? now}) {
    if (!const {'wear_os_sensor', 'ble_hr'}.contains(source)) {
      return 'La fuente de la lectura no es un sensor compatible.';
    }
    if (deviceName.trim().isEmpty || deviceName.length > 100) {
      return 'El nombre del dispositivo no es válido.';
    }
    if (heartRateBpm < 30 || heartRateBpm > 220) {
      return 'La frecuencia cardiaca está fuera del rango de captura permitido.';
    }
    final spo2 = oxygenSaturationPercent;
    if (spo2 != null && (spo2 < 50 || spo2 > 100)) {
      return 'El valor de SpO₂ está fuera del rango de captura permitido.';
    }
    final temperature = bodyTemperatureCelsius;
    if (temperature != null &&
        (!temperature.isFinite || temperature < 25 || temperature > 45)) {
      return 'La temperatura está fuera del rango de captura permitido.';
    }
    if (sensorReadings.length > 64 ||
        sensorReadings.entries.any(
          (entry) =>
              entry.key.trim().isEmpty ||
              entry.key.length > 64 ||
              entry.value.label.trim().isEmpty ||
              entry.value.label.length > 100 ||
              entry.value.unit.length > 32 ||
              entry.value.values.length > 16 ||
              entry.value.values.any((value) => !value.isFinite),
        )) {
      return 'Los datos adicionales de sensores no son válidos.';
    }
    final currentTime = now ?? DateTime.now();
    final maxAge = source == 'wear_os_sensor'
        ? wearOsCaptureMaxAge
        : const Duration(minutes: 5);
    if (readingAt.isAfter(currentTime.add(const Duration(minutes: 2))) ||
        currentTime.difference(readingAt) > maxAge) {
      return 'La lectura está vencida. Sincroniza el reloj y vuelve a intentarlo.';
    }
    return null;
  }
}

class WearableMeasurement {
  const WearableMeasurement({
    required this.id,
    required this.ownerUid,
    required this.readingAt,
    required this.createdAt,
    required this.source,
    required this.deviceName,
    required this.heartRateBpm,
    this.oxygenSaturationPercent,
    this.bodyTemperatureCelsius,
    this.sensorReadings = const {},
  });

  final String id;
  final String ownerUid;
  final DateTime readingAt;
  final DateTime createdAt;
  final String source;
  final String deviceName;
  final int heartRateBpm;
  final int? oxygenSaturationPercent;
  final double? bodyTemperatureCelsius;
  final Map<String, WearableSensorReadingRecord> sensorReadings;

  factory WearableMeasurement.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final ownerUid = data['ownerUid'] ?? data['owner_uid'];
    final source = data['source'];
    final deviceName = data['deviceName'] ?? data['device_name'];
    final heartRateBpm = data['heartRateBpm'] ?? data['heart_rate_bpm'];
    if (id is! String ||
        ownerUid is! String ||
        source is! String ||
        deviceName is! String ||
        heartRateBpm is! num) {
      throw const FormatException('La API devolvió una medición inválida.');
    }
    return WearableMeasurement(
      id: id,
      ownerUid: ownerUid,
      readingAt: _dateTime(data['readingAt'] ?? data['reading_at']),
      createdAt: _dateTime(data['createdAt'] ?? data['created_at']),
      source: source,
      deviceName: deviceName,
      heartRateBpm: heartRateBpm.round(),
      oxygenSaturationPercent: _optionalInt(
        data['oxygenSaturationPercent'] ?? data['oxygen_saturation_percent'],
      ),
      bodyTemperatureCelsius: _optionalDouble(
        data['bodyTemperatureCelsius'] ?? data['body_temperature_celsius'],
      ),
      sensorReadings: _parseSensorReadings(
        data['sensorReadings'] ?? data['sensor_readings'],
      ),
    );
  }

  static int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.round();
    throw const FormatException('Una medición tiene SpO₂ inválida.');
  }

  static double? _optionalDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw const FormatException('Una medición tiene temperatura inválida.');
  }

  static DateTime _dateTime(Object? value) {
    if (value is String) return DateTime.parse(value);
    if (value is DateTime) return value;
    throw const FormatException('Una medición tiene una fecha inválida.');
  }
}

class WearableSensorReadingRecord {
  const WearableSensorReadingRecord({
    required this.label,
    required this.unit,
    required this.values,
    this.observedAt,
  });

  final String label;
  final String unit;
  final List<double> values;
  final DateTime? observedAt;

  Map<String, Object?> toJson() => {
    'label': label,
    'unit': unit,
    'values': values,
    if (observedAt != null) 'observedAt': observedAt!.toUtc().toIso8601String(),
  };

  factory WearableSensorReadingRecord.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Una lectura adicional de sensor no es válida.',
      );
    }
    final label = value['label'];
    final unit = value['unit'];
    final values = value['values'];
    if (label is! String || unit is! String || values is! List) {
      throw const FormatException(
        'Una lectura adicional de sensor está incompleta.',
      );
    }
    if (values.length > 16 ||
        values.any((item) => item is! num || !item.isFinite)) {
      throw const FormatException(
        'Una lectura adicional de sensor no es válida.',
      );
    }
    return WearableSensorReadingRecord(
      label: label,
      unit: unit,
      values: values.cast<num>().map((item) => item.toDouble()).toList(),
      observedAt: _optionalDateTime(value['observedAt']),
    );
  }
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const FormatException(
    'La fecha de lectura adicional del sensor no es válida.',
  );
}

Map<String, WearableSensorReadingRecord> _parseSensorReadings(Object? value) {
  if (value is String) value = jsonDecode(value);
  if (value == null) return const {};
  if (value is! Map || value.length > 64) {
    throw const FormatException(
      'La lista de lecturas de sensores no es válida.',
    );
  }
  final readings = <String, WearableSensorReadingRecord>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'El identificador de un sensor no es válido.',
      );
    }
    readings[entry.key as String] = WearableSensorReadingRecord.fromJson(
      entry.value,
    );
  }
  return Map.unmodifiable(readings);
}

Map<String, Object?> _sensorReadingsToJson(
  Map<String, WearableSensorReadingRecord> readings,
) => {for (final entry in readings.entries) entry.key: entry.value.toJson()};
