import 'package:cloud_firestore/cloud_firestore.dart';

class HealthReport {
  const HealthReport({
    required this.id,
    required this.equipment,
    required this.description,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.pendingSync = false,
  });

  final String id;
  final String equipment;
  final String description;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pendingSync;

  factory HealthReport.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool pendingSync = false,
  }) => HealthReport(
    id: id,
    equipment: data['equipment'] as String,
    description: data['description'] as String,
    priority: data['priority'] as String,
    createdAt: _dateTime(data['createdAt']),
    updatedAt: _dateTime(data['updatedAt']),
    pendingSync: pendingSync,
  );

  static DateTime _dateTime(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => DateTime.now(),
  };
}

class HealthReportDraft {
  const HealthReportDraft({
    required this.id,
    required this.equipment,
    required this.description,
    required this.priority,
  });

  final String id;
  final String equipment;
  final String description;
  final String priority;
}
