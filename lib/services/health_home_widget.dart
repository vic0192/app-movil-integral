import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HealthHomeWidget {
  static const _channel = MethodChannel('com.biomedica/health_widget');
  static const _actionsChannel = EventChannel(
    'com.biomedica/health_widget_actions',
  );

  static Stream<void> get urgentCallRequests => _actionsChannel
      .receiveBroadcastStream()
      .where(
        (event) => event is Map && event['action'] == 'urgent_call',
      )
      .map((_) {});

  static Future<void> update({
    required int? heartRate,
    required int? oxygenSaturation,
    required String? bloodPressure,
    required DateTime? updatedAt,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('update', {
        'heartRate': heartRate,
        'spo2': oxygenSaturation,
        'bloodPressure': bloodPressure,
        'updatedAt': updatedAt == null
            ? null
            : '${updatedAt.hour.toString().padLeft(2, '0')}:'
                  '${updatedAt.minute.toString().padLeft(2, '0')}',
      });
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo actualizar el widget BioMedica: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<bool> requestPin() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;

    try {
      return await _channel.invokeMethod<bool>('pin') ?? false;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('No se pudo añadir el widget BioMedica: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}
