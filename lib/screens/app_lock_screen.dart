import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../services/app_lock_service.dart';

class AppLockUnlockScreen extends StatefulWidget {
  const AppLockUnlockScreen({
    super.key,
    required this.lockService,
    required this.onUnlocked,
  });

  final AppLockService lockService;
  final VoidCallback onUnlocked;

  @override
  State<AppLockUnlockScreen> createState() => _AppLockUnlockScreenState();
}

class _AppLockUnlockScreenState extends State<AppLockUnlockScreen> {
  final _passwordController = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final valid = await widget.lockService.verify(_passwordController.text);
      if (!mounted) return;
      if (valid) {
        widget.onUnlocked();
      } else {
        setState(() => _error = 'La contraseña no es correcta.');
        _passwordController.clear();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo validar la contraseña: $error');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: BioMedicaColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: BioMedicaColors.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1410264D),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _brandMark(),
                  const SizedBox(height: 22),
                  const Icon(
                    Icons.lock_rounded,
                    color: BioMedicaColors.primary,
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'App protegida',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ingresa tu contraseña para consultar tu información de salud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BioMedicaColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  _passwordField(
                    controller: _passwordController,
                    label: 'Contraseña',
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: BioMedicaColors.red,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _unlock,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: const Text('Desbloquear'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({
    super.key,
    required this.lockService,
    required this.onChanged,
  });

  final AppLockService lockService;
  final ValueChanged<bool> onChanged;

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool? _enabled;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final enabled = await widget.lockService.isEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo consultar la protección: $error');
      }
    }
  }

  Future<void> _savePassword() async {
    if (_enabled == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_enabled! &&
          !await widget.lockService.verify(_currentController.text)) {
        setState(() => _error = 'La contraseña actual no es correcta.');
        return;
      }
      if (_passwordController.text.trim().length <
              AppLockService.minimumPasswordLength ||
          _passwordController.text.length > 128) {
        setState(
          () => _error = 'Usa una contraseña de entre 8 y 128 caracteres.',
        );
        return;
      }
      if (_passwordController.text != _confirmationController.text) {
        setState(() => _error = 'Las contraseñas no coinciden.');
        return;
      }
      await widget.lockService.setPassword(_passwordController.text);
      if (!mounted) return;
      widget.onChanged(true);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo guardar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disablePassword() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!await widget.lockService.verify(_currentController.text)) {
        setState(() => _error = 'La contraseña actual no es correcta.');
        return;
      }
      await widget.lockService.removePassword();
      if (!mounted) return;
      widget.onChanged(false);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo desactivar: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad de la app'),
        backgroundColor: BioMedicaColors.canvas,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [BioMedicaColors.primary, Color(0xFF2D7BE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.shield_moon_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Protege tus datos de salud con una contraseña local.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (enabled == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _statusCard(enabled),
                  const SizedBox(height: 18),
                  if (enabled)
                    _passwordField(
                      controller: _currentController,
                      label: 'Contraseña actual',
                    ),
                  if (enabled) const SizedBox(height: 12),
                  _passwordField(
                    controller: _passwordController,
                    label: 'Nueva contraseña',
                  ),
                  const SizedBox(height: 12),
                  _passwordField(
                    controller: _confirmationController,
                    label: 'Confirmar contraseña',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Debe tener al menos 8 caracteres. Se guarda de forma segura en este dispositivo y no se envía al servidor.',
                    style: TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: BioMedicaColors.red),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _savePassword,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      enabled ? 'Cambiar contraseña' : 'Activar protección',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _disablePassword,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Desactivar protección'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: BioMedicaColors.red,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(bool enabled) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: enabled ? BioMedicaColors.greenLight : BioMedicaColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BioMedicaColors.line),
    ),
    child: Row(
      children: [
        Icon(
          enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
          color: enabled ? BioMedicaColors.green : BioMedicaColors.primary,
        ),
        const SizedBox(width: 10),
        Text(
          enabled ? 'Protección activada' : 'Protección desactivada',
          style: const TextStyle(
            color: BioMedicaColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget _brandMark() => ClipRRect(
  borderRadius: BorderRadius.circular(18),
  child: Image.asset(
    'assets/icon/biomedica_launcher.png',
    width: 72,
    height: 72,
    fit: BoxFit.cover,
  ),
);

Widget _passwordField({
  required TextEditingController controller,
  required String label,
  ValueChanged<String>? onSubmitted,
}) => TextField(
  controller: controller,
  obscureText: true,
  autocorrect: false,
  enableSuggestions: false,
  textInputAction: onSubmitted == null
      ? TextInputAction.next
      : TextInputAction.done,
  onSubmitted: onSubmitted,
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: const Icon(Icons.lock_outline_rounded),
    filled: true,
    fillColor: BioMedicaColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: BioMedicaColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: BioMedicaColors.line),
    ),
  ),
);
