import 'package:characters/characters.dart';

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

  factory HealthReport.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final equipment = data['equipment'];
    final description = data['description'];
    final priority = data['priority'];
    final createdAt = data['createdAt'] ?? data['created_at'];
    final updatedAt = data['updatedAt'] ?? data['updated_at'];
    if (id is! String ||
        equipment is! String ||
        description is! String ||
        priority is! String) {
      throw const FormatException('La API devolvió un reporte inválido.');
    }
    return HealthReport(
      id: id,
      equipment: equipment,
      description: description,
      priority: priority,
      createdAt: _dateTime(createdAt),
      updatedAt: _dateTime(updatedAt),
    );
  }

  static DateTime _dateTime(Object? value) {
    if (value is String) return DateTime.parse(value);
    if (value is DateTime) return value;
    throw const FormatException('Un reporte tiene una fecha inválida.');
  }
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

class HealthReportValidation {
  static const maxIdLength = 100;
  static const maxEquipmentLength = 100;
  static const maxDescriptionLength = 500;
  static const priorities = ['Baja', 'Media', 'Alta'];

  static String? id(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    if (normalized.contains('/')) return 'El ID no puede contener /.';
    if (normalized.characters.length > maxIdLength) {
      return 'Máximo $maxIdLength caracteres.';
    }
    return null;
  }

  static String? equipment(String? value) =>
      _requiredText(value, 'el equipo', maxEquipmentLength);

  static String? description(String? value) =>
      _requiredText(value, 'la descripción', maxDescriptionLength);

  static String? priority(String? value) =>
      priorities.contains(value) ? null : 'Selecciona una prioridad válida.';

  static String? _requiredText(String? value, String label, int maximum) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Escribe $label.';
    if (normalized.characters.length > maximum) {
      return 'Máximo $maximum caracteres.';
    }
    return null;
  }
}
