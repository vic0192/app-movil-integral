enum AppRole { patient, doctor, admin }

extension AppRoleLabel on AppRole {
  String get label => switch (this) {
    AppRole.patient => 'Paciente',
    AppRole.doctor => 'Médico',
    AppRole.admin => 'Administrador',
  };
}

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.assignedPatientUids = const [],
    this.firstName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.chronicConditions = const [],
    this.otherChronicCondition,
  });

  final String uid;
  final String displayName;
  final String email;
  final AppRole role;
  final List<String> assignedPatientUids;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final List<String> chronicConditions;
  final String? otherChronicCondition;

  factory AppUserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final roleName = data['role'];
    final role = switch (roleName) {
      'patient' => AppRole.patient,
      'doctor' => AppRole.doctor,
      'admin' => AppRole.admin,
      _ => throw const FormatException(
        'El perfil no tiene un rol válido. Contacta al administrador.',
      ),
    };
    final assigned = data['assignedPatientUids'];
    final firstName = data['first_name'] ?? data['firstName'];
    final lastName = data['last_name'] ?? data['lastName'];
    final name = data['displayName'];
    final displayName = name is String
        ? name
        : '${firstName is String ? firstName : ''} '
                  '${lastName is String ? lastName : ''}'
              .trim();
    final email = data['email'];
    final rawConditions =
        data['chronic_conditions'] ?? data['chronicConditions'];
    final rawOtherCondition =
        data['other_chronic_condition'] ?? data['otherChronicCondition'];
    return AppUserProfile(
      uid: uid,
      displayName: displayName,
      email: email is String ? email : '',
      role: role,
      assignedPatientUids: assigned is List
          ? assigned.whereType<String>().toList(growable: false)
          : const [],
      firstName: firstName is String ? firstName : '',
      lastName: lastName is String ? lastName : '',
      dateOfBirth: _dateOnly(data['date_of_birth'] ?? data['dateOfBirth']),
      chronicConditions: rawConditions is List
          ? rawConditions.whereType<String>().toList(growable: false)
          : const [],
      otherChronicCondition: rawOtherCondition is String
          ? rawOtherCondition
          : null,
    );
  }

  factory AppUserProfile.fromSupabase(
    String uid,
    String email,
    Map<String, dynamic> data,
  ) => AppUserProfile.fromMap(uid, {...data, 'email': email});

  static DateTime? _dateOnly(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    return null;
  }
}
