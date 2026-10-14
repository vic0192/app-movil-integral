import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onContinue});

  final void Function(String name, String email) onContinue;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const _maxUsernameLength = 30;
  static const _maxPasswordLength = 30;
  static const _demoUsername = 'paciente';
  static const _demoPassword = 'BioMedica2026';

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final username = _email.text.trim();
    if (!_registering &&
        (username != _demoUsername || _password.text != _demoPassword)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo iniciar sesión. Verifica tus datos e inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }

    final email = !_registering ? 'paciente@biomedica.mx' : username;
    final name = _registering && _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : !_registering
        ? 'Paciente de demostración'
        : username
              .split('@')
              .first
              .split(RegExp(r'[._-]'))
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Acceso simulado correcto.')));
    widget.onContinue(name, email);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 430,
                minHeight: constraints.hasBoundedHeight
                    ? (constraints.maxHeight - 50)
                          .clamp(0.0, constraints.maxHeight)
                          .toDouble()
                    : 0.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _brand(),
                  const SizedBox(height: 38),
                  Text(
                    _registering ? 'Crea tu cuenta' : 'Tu salud, más cerca.',
                    style: const TextStyle(
                      color: BioMedicaColors.ink,
                      fontSize: 30,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _registering
                        ? 'Comienza a seguir tus signos vitales y tu turno.'
                        : 'Consulta tus signos vitales y sigue tu turno desde un solo lugar.',
                    style: const TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: BioMedicaColors.line),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A10264D),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                        BoxShadow(
                          color: Color(0xBFFFFFFF),
                          blurRadius: 12,
                          offset: Offset(-4, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_registering) ...[
                                _label('Nombre completo'),
                                TextFormField(
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  decoration: _decoration(
                                    'Ej. Valeria Mora',
                                    Icons.person_outline_rounded,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().length < 3
                                      ? 'Escribe tu nombre completo.'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              _label(
                                _registering ? 'Correo electrónico' : 'Usuario',
                              ),
                              TextFormField(
                                controller: _email,
                                keyboardType: _registering
                                    ? TextInputType.emailAddress
                                    : TextInputType.text,
                                maxLength: _registering
                                    ? 254
                                    : _maxUsernameLength,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration(
                                  _registering
                                      ? 'tu@correo.com'
                                      : 'Nombre de usuario',
                                  _registering
                                      ? Icons.mail_outline_rounded
                                      : Icons.person_outline_rounded,
                                ).copyWith(counterText: ''),
                                validator: (value) {
                                  final username = value?.trim() ?? '';
                                  // Rechaza valores vacíos o formados solo por espacios.
                                  if (username.isEmpty) {
                                    return 'Ingresa tu usuario.';
                                  }
                                  // El límite se comprueba también en el validador, no solo en la interfaz.
                                  final maxLength = _registering
                                      ? 254
                                      : _maxUsernameLength;
                                  if (username.length > maxLength) {
                                    return 'El usuario excede la longitud permitida.';
                                  }
                                  if (_registering && !username.contains('@')) {
                                    return 'Ingresa un correo válido.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _label('Contraseña'),
                              TextFormField(
                                controller: _password,
                                obscureText: _hidePassword,
                                maxLength: _maxPasswordLength,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration:
                                    _decoration(
                                          'Mínimo 8 caracteres',
                                          Icons.lock_outline_rounded,
                                        )
                                        .copyWith(
                                          suffixIcon: IconButton(
                                            tooltip: _hidePassword
                                                ? 'Mostrar contraseña'
                                                : 'Ocultar contraseña',
                                            onPressed: () => setState(
                                              () => _hidePassword =
                                                  !_hidePassword,
                                            ),
                                            icon: Icon(
                                              _hidePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                          ),
                                        )
                                        .copyWith(counterText: ''),
                                validator: (value) {
                                  final password = value ?? '';
                                  // La contraseña debe tener entre 8 y 64 caracteres.
                                  if (password.length < 8) {
                                    return 'Usa al menos 8 caracteres.';
                                  }
                                  if (password.length > _maxPasswordLength) {
                                    return 'La contraseña excede la longitud permitida.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: Text(
                                  _registering
                                      ? 'Crear cuenta'
                                      : 'Iniciar sesión',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _registering = !_registering),
                            child: Text(
                              _registering
                                  ? 'Ya tengo una cuenta'
                                  : 'Crear una cuenta',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: BioMedicaColors.line, height: 28),
                  OutlinedButton.icon(
                    onPressed: () => widget.onContinue(
                      'Valeria Mora',
                      'valeria.mora@biomedica.mx',
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 19),
                    label: const Text('Explorar demostración'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: BioMedicaColors.ink,
                      side: const BorderSide(color: BioMedicaColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Acceso simulado · credenciales de prueba descritas en README.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'La autenticación real debe realizarse y validarse en un servidor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BioMedicaColors.muted,
                      fontSize: 11,
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

  Widget _brand() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: BioMedicaColors.primary,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(
          Icons.monitor_heart_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
      const SizedBox(width: 12),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BioMedica',
            style: TextStyle(
              color: BioMedicaColors.ink,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'PACIENTE',
            style: TextStyle(
              color: BioMedicaColors.red,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        color: BioMedicaColors.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: BioMedicaColors.muted, size: 20),
    filled: true,
    fillColor: BioMedicaColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: BioMedicaColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: BioMedicaColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: BioMedicaColors.primary, width: 1.5),
    ),
  );
}
