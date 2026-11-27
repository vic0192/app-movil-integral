import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bio_medica_colors.dart';
import 'data/account_repository.dart';
import 'data/supabase_config.dart';
import 'models/app_user_profile.dart';
import 'screens/app_lock_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/clinical_record_screen.dart';
import 'screens/measurement_records_screen.dart';
import 'screens/patient_shell.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/app_lock_service.dart';
import 'services/supabase_connectivity_monitor.dart';

class BioMedicaApp extends StatefulWidget {
  const BioMedicaApp({super.key, this.accountRepository, this.appLockService});

  final AccountRepository? accountRepository;
  final AppLockService? appLockService;

  @override
  State<BioMedicaApp> createState() => _BioMedicaAppState();
}

class _BioMedicaAppState extends State<BioMedicaApp>
    with WidgetsBindingObserver {
  late final AccountRepository _accounts =
      widget.accountRepository ?? SupabaseAccountRepository();
  late final AppLockService _appLockService =
      widget.appLockService ?? AppLockService();
  AppUserProfile? _profile;
  String? _restoreError;
  bool _recoveringPassword = false;
  bool _appLockEnabled = false;
  bool _appLockLoaded = false;
  bool _appLocked = false;
  bool _appLockLoadFailed = false;
  StreamSubscription<AuthState>? _authSubscription;
  SupabaseConnectivityMonitor? _connectivityMonitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode && SupabaseConfig.isConfigured) {
      final monitor = SupabaseConnectivityMonitor(
        supabaseUrl: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
        onResult: (result) => debugPrint('Supabase health check: $result'),
      );
      _connectivityMonitor = monitor;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        monitor.start();
      }
    }
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
    unawaited(_restoreSession(appStart: true));
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _connectivityMonitor?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectivityMonitor?.start();
    } else {
      _connectivityMonitor?.stop();
    }
    if (state == AppLifecycleState.paused &&
        _appLockEnabled &&
        _profile != null &&
        !_appLocked) {
      setState(() => _appLocked = true);
    }
  }

  Future<void> _restoreSession({bool appStart = false}) async {
    var lockEnabled = _appLockEnabled;
    final checkLock = appStart || !_appLockLoaded;
    if (checkLock) {
      try {
        lockEnabled = await _appLockService.isEnabled();
        if (mounted) {
          setState(() {
            _appLockEnabled = lockEnabled;
            _appLockLoaded = true;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _restoreError = '$error';
            _appLockLoadFailed = true;
          });
        }
        return;
      }
    }

    try {
      final profile = await _accounts.restoreSession();
      if (mounted) {
        setState(() {
          _appLockEnabled = lockEnabled;
          _profile = profile;
          _appLocked = lockEnabled && profile != null;
          _appLockLoadFailed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _restoreError = '$error';
          _appLockEnabled = lockEnabled;
          _appLocked = false;
          _appLockLoadFailed = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await _accounts.signOut();
    if (mounted) {
      setState(() {
        _profile = null;
        _appLocked = false;
      });
    }
  }

  void _onAppLockChanged(bool enabled) {
    if (mounted) {
      setState(() {
        _appLockEnabled = enabled;
        _appLockLoaded = true;
        _appLocked = false;
      });
    }
  }

  void _unlockApp() {
    if (mounted) setState(() => _appLocked = false);
  }

  Widget _home() {
    if (_appLockLoadFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: BioMedicaColors.red,
                  size: 36,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No se pudo verificar la protección local.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BioMedicaColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _restoreError ?? 'Reinicia la app e inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BioMedicaColors.muted),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _restoreError = null);
                    unawaited(_restoreSession(appStart: true));
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_appLockLoaded && _profile != null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_appLocked && _profile != null) {
      return AppLockUnlockScreen(
        lockService: _appLockService,
        onUnlocked: _unlockApp,
      );
    }
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
        onContinue: (user) => setState(() {
          _profile = user;
          _appLocked = _appLockEnabled;
        }),
      );
    }
    if (profile.role == AppRole.patient) {
      return PatientShell(
        patientUid: profile.uid,
        patientName: profile.displayName,
        patientEmail: profile.email,
        chronicConditions: profile.chronicConditions,
        onSignOut: _signOut,
        appLockService: _appLockService,
        appLockEnabled: _appLockEnabled,
        onAppLockChanged: _onAppLockChanged,
      );
    }
    return _StaffShell(
      profile: profile,
      onSignOut: _signOut,
      appLockService: _appLockService,
      appLockEnabled: _appLockEnabled,
      onAppLockChanged: _onAppLockChanged,
    );
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

class _StaffShell extends StatefulWidget {
  const _StaffShell({
    required this.profile,
    required this.onSignOut,
    required this.appLockService,
    required this.appLockEnabled,
    required this.onAppLockChanged,
  });

  final AppUserProfile profile;
  final VoidCallback onSignOut;
  final AppLockService appLockService;
  final bool appLockEnabled;
  final ValueChanged<bool> onAppLockChanged;

  @override
  State<_StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<_StaffShell> {
  int _refreshKey = 0;

  Future<void> _refresh() async {
    setState(() => _refreshKey++);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _manageAppLock() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppLockSettingsScreen(
          lockService: widget.appLockService,
          onChanged: widget.onAppLockChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: widget.profile.role == AppRole.admin ? 4 : 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text('BioMedica · ${widget.profile.role.label}'),
        actions: [
          IconButton(
            tooltip: widget.appLockEnabled
                ? 'Cambiar contraseña de la app'
                : 'Configurar contraseña de la app',
            onPressed: _manageAppLock,
            icon: Icon(
              widget.appLockEnabled
                  ? Icons.lock_rounded
                  : Icons.lock_outline_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onSignOut,
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
            const Tab(
              icon: Icon(Icons.folder_shared_outlined),
              text: 'Expediente',
            ),
            if (widget.profile.role == AppRole.admin)
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
            child: RefreshIndicator(
              onRefresh: _refresh,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.vertical,
              child: TabBarView(
                children: [
                  ReportsScreen(
                    key: ValueKey('reports-$_refreshKey'),
                    patientName: widget.profile.displayName,
                  ),
                  MeasurementRecordsScreen(
                    key: ValueKey('measurements-$_refreshKey'),
                  ),
                  ClinicalRecordScreen(
                    key: ValueKey('clinical-record-$_refreshKey'),
                    canEdit: widget.profile.role == AppRole.doctor,
                  ),
                  if (widget.profile.role == AppRole.admin)
                    AdminUsersScreen(key: ValueKey('users-$_refreshKey')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
