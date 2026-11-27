import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/admin_user_repository.dart';
import '../models/app_user_profile.dart';
import 'admin_clinic_turns_section.dart';

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
  Stream<List<DoctorCredentialRequest>>? _doctorApplications;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    try {
      _users = _repository.watchUsers();
      _doctorApplications = _repository.watchDoctorApplications();
    } catch (error) {
      _error = 'No se pudo iniciar la administración. Inténtalo más tarde.';
    }
  }

  Future<void> _reviewDoctorApplication(
    DoctorCredentialRequest request,
    AppUserProfile? user, {
    required bool approve,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Verificar solicitud' : 'Rechazar solicitud'),
        content: Text(
          approve
              ? 'Confirma que verificaste la cédula profesional de '
                    '${user?.displayName ?? 'este solicitante'} en una fuente '
                    'oficial antes de aprobarla.'
              : '¿Rechazar la solicitud de '
                    '${user?.displayName ?? 'este solicitante'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Verificar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.reviewDoctorApplication(
        request.doctorUid,
        approve: approve,
      );
      _message(
        approve
            ? 'Solicitud verificada. La cuenta ya tiene rol de médico.'
            : 'Solicitud rechazada.',
      );
    } on AdminUserException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudo revisar la solicitud. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
      _message('No se pudo actualizar el rol. Inténtalo de nuevo.');
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
      builder: (context) =>
          _AssignmentDialog(doctor: doctor, patients: patients),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.updateDoctorAssignments(doctor.uid, selected);
      _message(
        '${selected.length} paciente(s) asignado(s) a ${doctor.displayName}.',
      );
    } on AdminUserException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('No se pudieron guardar las asignaciones. Inténtalo de nuevo.');
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
      return _scrollState(
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(color: BioMedicaColors.red),
        ),
      );
    }
    final stream = _users;
    if (stream == null) {
      return _scrollState(const CircularProgressIndicator());
    }
    return StreamBuilder<List<AppUserProfile>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _scrollState(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No se pudieron cargar las cuentas. Actualiza la página e '
                  'inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _users = _repository.watchUsers();
                    _doctorApplications =
                        _repository.watchDoctorApplications();
                  }),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return _scrollState(const CircularProgressIndicator());
        }
        final users = snapshot.data!;
        final patients = users
            .where((user) => user.role == AppRole.patient)
            .toList(growable: false);
        return StreamBuilder<List<DoctorCredentialRequest>>(
          stream: _doctorApplications,
          builder: (context, applicationsSnapshot) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _doctorApplicationsSection(
                applicationsSnapshot,
                users,
              ),
              const SizedBox(height: 12),
              AdminClinicTurnsSection(patients: patients),
              const SizedBox(height: 12),
              _accountsSection(users, patients),
            ],
          ),
        );
      },
    );
  }

  Widget _doctorApplicationsSection(
    AsyncSnapshot<List<DoctorCredentialRequest>> snapshot,
    List<AppUserProfile> users,
  ) {
    final usersByUid = {for (final user in users) user.uid: user};
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Solicitudes de médicos',
              style: TextStyle(
                color: BioMedicaColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No se pudieron cargar las solicitudes. Inténtalo de nuevo.',
                      style: TextStyle(color: BioMedicaColors.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reintentar solicitudes',
                    onPressed: () => setState(
                      () => _doctorApplications =
                          _repository.watchDoctorApplications(),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              )
            else if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.data!.isEmpty)
              const Text(
                'No hay solicitudes pendientes.',
                style: TextStyle(color: BioMedicaColors.muted),
              )
            else ...[
              const Text(
                'Verifica la cédula profesional en una fuente oficial antes '
                'de aprobar al solicitante.',
                style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
              ),
              for (final request in snapshot.data!)
                _doctorApplicationTile(request, usersByUid[request.doctorUid]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doctorApplicationTile(
    DoctorCredentialRequest request,
    AppUserProfile? user,
  ) => Card(
    color: BioMedicaColors.canvas,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            user?.displayName.isNotEmpty == true
                ? user!.displayName
                : 'Solicitante ${request.doctorUid.substring(0, 8)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (user?.email.isNotEmpty == true)
            Text(
              user!.email,
              style: const TextStyle(
                color: BioMedicaColors.muted,
                fontSize: 12,
              ),
            ),
          Text('Cédula profesional: ${request.professionalLicense}'),
          if (request.specialty?.isNotEmpty == true)
            Text('Especialidad: ${request.specialty}'),
          if (request.specialtyLicense?.isNotEmpty == true)
            Text('Cédula de especialidad: ${request.specialtyLicense}'),
          if (request.institution?.isNotEmpty == true)
            Text('Institución: ${request.institution}'),
          if (request.contactPhone?.isNotEmpty == true)
            Text('Teléfono: ${request.contactPhone}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _reviewDoctorApplication(
                        request,
                        user,
                        approve: true,
                      ),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verificar'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _reviewDoctorApplication(
                        request,
                        user,
                        approve: false,
                      ),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Rechazar'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _accountsSection(
    List<AppUserProfile> users,
    List<AppUserProfile> patients,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Usuarios',
            style: TextStyle(
              color: BioMedicaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Las cuentas nuevas comienzan como pacientes. El rol médico se '
            'asigna al aprobar una solicitud.',
            style: TextStyle(color: BioMedicaColors.muted, fontSize: 12),
          ),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Aún no hay cuentas registradas.'),
            )
          else
            for (final user in users)
              _userTile(user, patients),
        ],
      ),
    ),
  );

  Widget _userTile(AppUserProfile user, List<AppUserProfile> patients) {
    final roles = user.role == AppRole.doctor
        ? AppRole.values
        : const [AppRole.patient, AppRole.admin];
    return Card(
      color: BioMedicaColors.canvas,
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
              items: roles
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
    );
  }

  Widget _scrollState(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.doctor, required this.patients});

  final AppUserProfile doctor;
  final List<AppUserProfile> patients;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  late final Set<String> _selected = widget.doctor.assignedPatientUids.toSet();

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
