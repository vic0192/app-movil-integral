class WearableMeasurementDraft {
  const WearableMeasurementDraft({
    required this.readingAt,
    required this.source,
    required this.deviceName,
    required this.heartRateBpm,
    this.oxygenSaturationPercent,
    this.bodyTemperatureCelsius,
  });

  final DateTime readingAt;
  final String source;
  final String deviceName;
  final int heartRateBpm;
  final int? oxygenSaturationPercent;
  final double? bodyTemperatureCelsius;

  Map<String, Object?> toJson() => {
    'readingAt': readingAt.toUtc().toIso8601String(),
    'source': source,
    'deviceName': deviceName.trim(),
    'heartRateBpm': heartRateBpm,
    'oxygenSaturationPercent': oxygenSaturationPercent,
    'bodyTemperatureCelsius': bodyTemperatureCelsius,
  };

  Map<String, Object?> toSupabaseMap() => {
    'reading_at': readingAt.toUtc().toIso8601String(),
    'source': source,
    'device_name': deviceName.trim(),
    'heart_rate_bpm': heartRateBpm,
    'oxygen_saturation_percent': oxygenSaturationPercent,
    'body_temperature_celsius': bodyTemperatureCelsius,
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
    final currentTime = now ?? DateTime.now();
    if (readingAt.isAfter(currentTime.add(const Duration(minutes: 2))) ||
        currentTime.difference(readingAt) > const Duration(minutes: 5)) {
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
