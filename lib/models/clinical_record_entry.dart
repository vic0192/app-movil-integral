import 'app_user_profile.dart';

enum ClinicalEntryType {
  diagnosis('diagnosis', 'Diagnóstico', 'medical_information_outlined'),
  clinicalNote('clinical_note', 'Nota clínica', 'description_outlined'),
  medication('medication', 'Medicamento', 'medication_outlined'),
  allergy('allergy', 'Alergia', 'warning_amber_rounded'),
  visit('visit', 'Consulta', 'event_note_outlined');

  const ClinicalEntryType(this.value, this.label, this.iconName);

  final String value;
  final String label;
  final String iconName;

  static ClinicalEntryType fromValue(String value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw FormatException('Tipo clínico desconocido: $value'),
  );
}

class ClinicalRecordEntry {
  const ClinicalRecordEntry({
    required this.id,
    required this.patientUid,
    required this.authorUid,
    required this.type,
    required this.title,
    required this.details,
    required this.occurredAt,
    required this.createdAt,
  });

  final String id;
  final String patientUid;
  final String authorUid;
  final ClinicalEntryType type;
  final String title;
  final String details;
  final DateTime occurredAt;
  final DateTime createdAt;

  factory ClinicalRecordEntry.fromMap(Map<String, dynamic> row) {
    final id = row['id'];
    final patientUid = row['patient_uid'];
    final authorUid = row['author_uid'];
    final entryType = row['entry_type'];
    final title = row['title'];
    final details = row['details'];
    if (id is! String ||
        patientUid is! String ||
        authorUid is! String ||
        entryType is! String ||
        title is! String ||
        details is! String) {
      throw const FormatException('La entrada del expediente no es válida.');
    }
    return ClinicalRecordEntry(
      id: id,
      patientUid: patientUid,
      authorUid: authorUid,
      type: ClinicalEntryType.fromValue(entryType),
      title: title,
      details: details,
      occurredAt: _parseDate(row['occurred_at']),
      createdAt: _parseDate(row['created_at']),
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    throw const FormatException('La entrada clínica tiene una fecha inválida.');
  }
}

class ClinicalRecordDraft {
  const ClinicalRecordDraft({
    required this.patientUid,
    required this.type,
    required this.title,
    required this.details,
    required this.occurredAt,
  });

  final String patientUid;
  final ClinicalEntryType type;
  final String title;
  final String details;
  final DateTime occurredAt;

  String? validate({DateTime? now}) {
    if (patientUid.isEmpty) return 'Selecciona un paciente.';
    if (title.trim().isEmpty || title.trim().length > 160) {
      return 'El título es obligatorio y no debe exceder 160 caracteres.';
    }
    if (details.trim().isEmpty || details.trim().length > 4000) {
      return 'Los detalles son obligatorios y no deben exceder 4000 caracteres.';
    }
    if (occurredAt.isAfter(now ?? DateTime.now())) {
      return 'La fecha de la entrada no puede estar en el futuro.';
    }
    return null;
  }
}

typedef ClinicalRecordPatient = AppUserProfile;
