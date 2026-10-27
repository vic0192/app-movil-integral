import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/account_repository.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    required this.repository,
    required this.onCompleted,
  });

  final AccountRepository repository;
  final VoidCallback onCompleted;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.updatePassword(_password.text);
      await widget.repository.signOut();
      if (mounted) widget.onCompleted();
    } on AccountRepositoryException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cambiar contraseña')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Elige una contraseña nueva',
                    style: TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Usa entre 8 y 30 caracteres.',
                    style: TextStyle(color: BioMedicaColors.muted),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    maxLength: 30,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      suffixIcon: IconButton(
                        tooltip: _hidePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      counterText: '',
                    ),
                    validator: (value) {
                      final length = value?.characters.length ?? 0;
                      if (length < 8) return 'Usa al menos 8 caracteres.';
                      if (length > 30) return 'Máximo 30 caracteres.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmation,
                    obscureText: true,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar contraseña',
                      counterText: '',
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Confirma tu contraseña.';
                      }
                      return value == _password.text
                          ? null
                          : 'Las contraseñas no coinciden.';
                    },
                    onFieldSubmitted: (_) => _savePassword(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _savePassword,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar contraseña'),
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
