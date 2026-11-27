import 'dart:convert';

import 'package:flutter/services.dart';

class WearOsDataLayer {
  WearOsDataLayer._();

  static const _methods = MethodChannel('com.biomedica/wearable');
  static const _events = EventChannel('com.biomedica/wearable_events');

  static Stream<Map<String, dynamic>> get readings => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  static Future<Map<String, dynamic>?> latest() async {
    final event = await _methods.invokeMapMethod<String, dynamic>('latest');
    return event;
  }

  static Future<List<WearOsNode>> connectedNodes() async {
    final nodes = await _methods.invokeListMethod<Object?>('connectedNodes');
    return (nodes ?? const <Object?>[])
        .whereType<Map>()
        .map((node) => WearOsNode.fromMap(Map<Object?, Object?>.from(node)))
        .toList(growable: false);
  }

  static Future<bool> openGalaxyWearable() async =>
      await _methods.invokeMethod<bool>('openGalaxyWearable') ?? false;

  static Future<void> acknowledgeCapture(String captureId) => _methods
      .invokeMethod<void>('acknowledgeCapture', {'captureId': captureId});

  static Map<String, WearOsSensorReading> parseSensorReadings(Object? payload) {
    final decoded = _decodePayload(payload);
    if (decoded == null) return const {};
    if (decoded is! Map) {
      throw const FormatException(
        'La lista de sensores del reloj no es válida.',
      );
    }
    return decoded.map((key, value) {
      if (key is! String || value is! Map) {
        throw const FormatException(
          'El reloj envió una medición de sensor inválida.',
        );
      }
      return MapEntry(
        key,
        WearOsSensorReading.fromMap(key, Map<Object?, Object?>.from(value)),
      );
    });
  }

  static List<WearOsSensorDescriptor> parseAvailableSensors(Object? payload) {
    final decoded = _decodePayload(payload);
    if (decoded == null) return const [];
    if (decoded is! List) {
      throw const FormatException('El inventario de sensores no es válido.');
    }
    if (decoded.any((sensor) => sensor is! Map)) {
      throw const FormatException('El inventario de sensores no es válido.');
    }
    return decoded
        .map(
          (sensor) => WearOsSensorDescriptor.fromMap(
            Map<Object?, Object?>.from(sensor as Map),
          ),
        )
        .toList(growable: false);
  }

  static Object? _decodePayload(Object? payload) {
    if (payload == null || payload == '') return null;
    return payload is String ? jsonDecode(payload) : payload;
  }
}

class WearOsNode {
  const WearOsNode({
    required this.id,
    required this.displayName,
    required this.isNearby,
  });

  final String id;
  final String displayName;
  final bool isNearby;

  factory WearOsNode.fromMap(Map<Object?, Object?> map) {
    final id = map['id'];
    final displayName = map['displayName'];
    if (id is! String || displayName is! String) {
      throw const FormatException('La información del reloj es inválida.');
    }
    return WearOsNode(
      id: id,
      displayName: displayName,
      isNearby: map['isNearby'] == true,
    );
  }
}

class WearOsSensorDescriptor {
  const WearOsSensorDescriptor({
    required this.key,
    required this.label,
    required this.unit,
    required this.permissionRequired,
    required this.isCollecting,
  });

  final String key;
  final String label;
  final String unit;
  final bool permissionRequired;
  final bool isCollecting;

  factory WearOsSensorDescriptor.fromMap(Map<Object?, Object?> map) {
    final key = map['key'];
    final label = map['label'];
    final unit = map['unit'];
    if (key is! String || label is! String || unit is! String) {
      throw const FormatException('El reloj anunció un sensor inválido.');
    }
    return WearOsSensorDescriptor(
      key: key,
      label: label,
      unit: unit,
      permissionRequired: map['permissionRequired'] == true,
      isCollecting: map['collecting'] == true,
    );
  }
}

class WearOsSensorReading {
  const WearOsSensorReading({
    required this.key,
    required this.label,
    required this.unit,
    required this.values,
    this.observedAt,
  });

  final String key;
  final String label;
  final String unit;
  final List<double> values;
  final DateTime? observedAt;

  factory WearOsSensorReading.fromMap(String key, Map<Object?, Object?> map) {
    final label = map['label'];
    final unit = map['unit'];
    final rawValues = map['values'];
    if (label is! String || unit is! String || rawValues is! List) {
      throw const FormatException('El reloj envió datos de sensor inválidos.');
    }
    if (rawValues.any((value) => value is! num || !value.isFinite)) {
      throw const FormatException(
        'El reloj envió valores de sensor inválidos.',
      );
    }
    final observedAt = _parseObservedAt(map['observedAt']);
    return WearOsSensorReading(
      key: key,
      label: label,
      unit: unit,
      values: rawValues
          .cast<num>()
          .map((value) => value.toDouble())
          .toList(growable: false),
      observedAt: observedAt,
    );
  }

  String get formattedValue {
    if (values.isEmpty) return '—';
    if (key == 'heart_rate' ||
        key == 'step_counter' ||
        key == 'step_detector') {
      return values.map((value) => value.round().toString()).join(' · ');
    }
    return values.map((value) => value.toStringAsFixed(2)).join(' · ');
  }

  static DateTime? _parseObservedAt(Object? value) {
    if (value == null) return null;
    if (value is num && value.isFinite) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('La fecha de lectura del sensor es inválida.');
  }
}
