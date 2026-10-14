import 'package:flutter/services.dart';

class WearOsDataLayer {
  WearOsDataLayer._();

  static const _methods = MethodChannel('com.biomedica/wearable');
  static const _events = EventChannel('com.biomedica/wearable_events');

  static Stream<Map<String, dynamic>> get readings =>
      _events.receiveBroadcastStream().where((event) => event is Map).map(
        (event) => Map<String, dynamic>.from(event as Map),
      );

  static Future<Map<String, dynamic>?> latest() async {
    final event = await _methods.invokeMapMethod<String, dynamic>('latest');
    return event;
  }
}
