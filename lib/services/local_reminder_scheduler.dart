import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/health_reminders.dart';

class LocalReminderScheduler {
  LocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  timezone.Location? _location;

  Future<bool> sync({
    required List<MedicationReminder> medications,
    required MeasurementReminderSettings? measurementSettings,
    bool requestPermission = true,
  }) async {
    await _initialize();
    final permissionGranted = requestPermission
        ? await _requestPermission()
        : true;
    await _plugin.cancelAll();

    for (final medication in medications.where((item) => item.enabled)) {
      final times = medication.dailyTimes;
      for (var index = 0; index < times.length; index++) {
        await _scheduleDaily(
          id: _notificationId('medication:${medication.id}:$index'),
          time: times[index],
          title: 'Recordatorio de medicina',
          body: 'Es hora de tomar tu medicamento.',
        );
      }
    }

    if (measurementSettings case final settings? when settings.enabled) {
      final count = 24 ~/ settings.intervalHours;
      final start = settings.firstMeasurementTime;
      for (var index = 0; index < count; index++) {
        final minutes =
            (start.hour * 60 +
                start.minute +
                index * settings.intervalHours * 60) %
            (24 * 60);
        await _scheduleDaily(
          id: _notificationId('measurement:$index'),
          time: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          title: 'Recordatorio de medición',
          body: 'Es hora de registrar tus signos vitales.',
        );
      }
    }
    return permissionGranted;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    _location = timezone.getLocation(timezoneInfo.identifier);
    timezone.setLocalLocation(_location!);
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> _scheduleDaily({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
  }) async {
    final now = timezone.TZDateTime.now(_location!);
    var scheduled = timezone.TZDateTime(
      _location!,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = timezone.TZDateTime(
        _location!,
        now.year,
        now.month,
        now.day + 1,
        time.hour,
        time.minute,
      );
    }
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'biomedica_health_reminders',
          'Recordatorios de salud',
          channelDescription: 'Avisos de medicamentos y mediciones',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
