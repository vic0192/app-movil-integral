import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bio_medica_colors.dart';
import 'data/account_repository.dart';
import 'data/supabase_config.dart';
import 'models/app_user_profile.dart';
import 'screens/admin_users_screen.dart';
import 'screens/measurement_records_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sign_in_screen.dart';

class BioMedicaApp extends StatefulWidget {
  const BioMedicaApp({super.key, this.accountRepository});

  final AccountRepository? accountRepository;

  @override
  State<BioMedicaApp> createState() => _BioMedicaAppState();
}

class _BioMedicaAppState extends State<BioMedicaApp> {
  late final AccountRepository _accounts =
      widget.accountRepository ?? SupabaseAccountRepository();
  AppUserProfile? _profile;
  String? _restoreError;
  bool _recoveringPassword = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.accountRepository == null && SupabaseConfig.isConfigured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.event == AuthChangeEvent.passwordRecovery && mounted) {
              setState(() => _recoveringPassword = true);
            }
            if (state.event == AuthChangeEvent.signedIn) {
              unawaited(_restoreSession());
            }
          });
    }
    unawaited(_restoreSession());
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final profile = await _accounts.restoreSession();
      if (mounted && profile != null) setState(() => _profile = profile);
    } catch (error) {
      if (mounted) setState(() => _restoreError = '$error');
    }
  }

  Future<void> _signOut() async {
    await _accounts.signOut();
    if (mounted) setState(() => _profile = null);
  }

  Widget _home() {
    if (_recoveringPassword) {
      return PasswordRecoveryScreen(
        repository: _accounts,
        onCompleted: () => setState(() {
          _recoveringPassword = false;
          _profile = null;
          _restoreError = null;
        }),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return SignInScreen(
        repository: _accounts,
        initialError: _restoreError,
        onContinue: (user) => setState(() => _profile = user),
      );
    }
    if (profile.role == AppRole.patient) {
      return PatientShell(
        patientName: profile.displayName,
        patientEmail: profile.email,
        chronicConditions: profile.chronicConditions,
        onSignOut: _signOut,
      );
    }
    return _StaffShell(profile: profile, onSignOut: _signOut);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BioMedica | Paciente',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BioMedicaColors.primary,
        primary: BioMedicaColors.primary,
        surface: BioMedicaColors.surface,
      ),
      scaffoldBackgroundColor: BioMedicaColors.canvas,
    ),
    home: _home(),
  );
}

class _StaffShell extends StatelessWidget {
  const _StaffShell({required this.profile, required this.onSignOut});

  final AppUserProfile profile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: profile.role == AppRole.admin ? 3 : 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text('BioMedica · ${profile.role.label}'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
        bottom: TabBar(
          tabs: [
            const Tab(icon: Icon(Icons.description_outlined), text: 'Reportes'),
            const Tab(
              icon: Icon(Icons.favorite_outline_rounded),
              text: 'Mediciones',
            ),
            if (profile.role == AppRole.admin)
              const Tab(
                icon: Icon(Icons.manage_accounts_outlined),
                text: 'Usuarios',
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: TabBarView(
              children: [
                ReportsScreen(patientName: profile.displayName),
                const MeasurementRecordsScreen(),
                if (profile.role == AppRole.admin) const AdminUsersScreen(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
