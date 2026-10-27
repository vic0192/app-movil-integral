import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/admin_user_repository.dart';
import '../models/app_user_profile.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.repository});

  final AdminUserRepository? repository;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminUserRepository _repository =
      widget.repository ?? AdminUserRepository();
  Stream<List<AppUserProfile>>? _users;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    try {
      _users = _repository.watchUsers();
    } catch (error) {
      _error = '$error';
    }
  }

  Future<void> _changeRole(AppUserProfile user, AppRole role) async {
    setState(() => _busy = true);
    try {
      await _repository.updateRole(user.uid, role);
      _message('Rol de ${user.displayName} actualizado.');
    } on AdminUserException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudo actualizar el rol: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAssignments(
    AppUserProfile doctor,
    List<AppUserProfile> patients,
  ) async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => _AssignmentDialog(
        doctor: doctor,
        patients: patients,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.updateDoctorAssignments(doctor.uid, selected);
      _message('${selected.length} paciente(s) asignado(s) a ${doctor.displayName}.');
    } on AdminUserException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudieron guardar las asignaciones: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudieron consultar las cuentas: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: BioMedicaColors.red),
          ),
        ),
      );
    }
    final stream = _users;
    if (stream == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<AppUserProfile>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'No se pudieron consultar las cuentas: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshot.data!;
        final patients = users
            .where((user) => user.role == AppRole.patient)
            .toList(growable: false);
        if (users.isEmpty) {
          return const Center(child: Text('Aún no hay cuentas registradas.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Text(
                'Asigna roles y pacientes. Las cuentas nuevas comienzan como pacientes.',
                style: TextStyle(color: BioMedicaColors.muted),
              ),
            ),
            for (final user in users)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BioMedicaColors.ink,
                        ),
                      ),
                      Text(
                        user.email,
                        style: const TextStyle(
                          color: BioMedicaColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<AppRole>(
                        key: ValueKey('role-${user.uid}'),
                        initialValue: user.role,
                        decoration: const InputDecoration(
                          labelText: 'Rol',
                          isDense: true,
                        ),
                        items: AppRole.values
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role.label),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (role) {
                                if (role != null && role != user.role) {
                                  _changeRole(user, role);
                                }
                              },
                      ),
                      if (user.role == AppRole.doctor)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _editAssignments(user, patients),
                            icon: const Icon(Icons.assignment_ind_outlined),
                            label: Text(
                              'Asignar pacientes (${user.assignedPatientUids.length})',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.doctor, required this.patients});

  final AppUserProfile doctor;
  final List<AppUserProfile> patients;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  late final Set<String> _selected =
      widget.doctor.assignedPatientUids.toSet();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Pacientes de ${widget.doctor.displayName}'),
    content: SizedBox(
      width: 380,
      child: widget.patients.isEmpty
          ? const Text('Registra cuentas de paciente para poder asignarlas.')
          : ListView(
              shrinkWrap: true,
              children: widget.patients
                  .map(
                    (patient) => CheckboxListTile(
                      value: _selected.contains(patient.uid),
                      title: Text(patient.displayName),
                      subtitle: Text(patient.email),
                      onChanged: (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(patient.uid);
                        } else {
                          _selected.remove(patient.uid);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selected.toList()),
        child: const Text('Guardar asignaciones'),
      ),
    ],
  );
}
