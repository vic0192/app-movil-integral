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
    this.malestar,
    this.otherMalestar,
    this.onsetAt,
  });

  final String id;
  final String equipment;
  final String description;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pendingSync;
  final String? malestar;
  final String? otherMalestar;
  final DateTime? onsetAt;

  factory HealthReport.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final equipment = data['equipment'];
    final malestar = data['malestar'];
    final otherMalestar = data['otherMalestar'];
    final onsetAt = data['onsetAt'];
    final description = data['description'];
    final priority = data['priority'];
    final createdAt = data['createdAt'] ?? data['created_at'];
    final updatedAt = data['updatedAt'] ?? data['updated_at'];
    if (id is! String ||
        (equipment is! String && malestar is! String) ||
        description is! String ||
        priority is! String) {
      throw const FormatException('La API devolvió un reporte inválido.');
    }
    return HealthReport(
      id: id,
      equipment: equipment is String ? equipment : malestar as String,
      description: description,
      priority: priority,
      createdAt: _dateTime(createdAt),
      updatedAt: _dateTime(updatedAt),
      malestar: malestar is String
          ? malestar
          : equipment is String
          ? equipment
          : null,
      otherMalestar: otherMalestar is String ? otherMalestar : null,
      onsetAt: onsetAt == null ? null : _dateTime(onsetAt),
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
    this.malestar,
    this.otherMalestar,
    this.onsetAt,
  });

  final String id;
  final String equipment;
  final String description;
  final String priority;
  final String? malestar;
  final String? otherMalestar;
  final DateTime? onsetAt;
}

class HealthReportValidation {
  static const maxIdLength = 100;
  static const maxEquipmentLength = 100;
  static const maxDescriptionLength = 500;
  static const maxMalestarLength = 100;
  static const priorities = ['Baja', 'Media', 'Alta'];
  static const malestares = [
    'Dolor de cabeza',
    'Mareo',
    'Falta de aire',
    'Tos',
    'Dolor en el pecho',
    'Palpitaciones',
    'Fiebre',
    'Náusea',
    'Cansancio',
    'Dolor articular',
    'Hinchazón',
    'Cambios en la visión',
    'Otro',
  ];

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

  static String? malestar(String? value) =>
      _requiredText(value, 'el malestar', maxMalestarLength);

  static String? otherMalestar(String? value, String? selected) {
    if (selected != 'Otro') return null;
    return _requiredText(value, 'el otro malestar', maxMalestarLength);
  }

  static String? onsetAt(DateTime value, {DateTime? now}) {
    if (value.isAfter(now ?? DateTime.now())) {
      return 'La fecha de inicio no puede estar en el futuro.';
    }
    return null;
  }

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
