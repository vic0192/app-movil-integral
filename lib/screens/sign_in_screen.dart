import 'package:flutter/material.dart';

import '../bio_medica_colors.dart';
import '../data/account_repository.dart';
import '../models/app_user_profile.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.onContinue,
    this.repository,
    this.initialError,
  });

  final ValueChanged<AppUserProfile> onContinue;
  final AccountRepository? repository;
  final String? initialError;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const _maxPasswordLength = 30;
  static const _maxNameLength = 100;
  static const _maxLastNameLength = 150;
  static const _otherCondition = 'Otra';
  static const _chronicConditionOptions = [
    'Hipertensión arterial',
    'Diabetes tipo 2',
    'Asma',
    'Enfermedad cardiovascular',
    'Enfermedad renal crónica',
    'Colesterol alto',
    'Enfermedad tiroidea',
    'EPOC',
    'Artritis',
    'Cáncer',
    _otherCondition,
  ];
  static final _emailPattern = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r'@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
  );

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _dateOfBirthText = TextEditingController();
  final _otherConditionText = TextEditingController();
  final _chronicConditions = <String>{};
  DateTime? _dateOfBirth;
  bool _registering = false;
  bool _hidePassword = true;
  bool _busy = false;
  late final AccountRepository _repository =
      widget.repository ?? SupabaseAccountRepository();

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _dateOfBirthText.dispose();
    _otherConditionText.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_registering) {
        final profile = await _repository.register(
          firstName: _name.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          dateOfBirth: _dateOfBirth!,
          chronicConditions: _chronicConditions
              .where((condition) => condition != _otherCondition)
              .toList(growable: false),
          otherChronicCondition: _chronicConditions.contains(_otherCondition)
              ? _otherConditionText.text.trim()
              : null,
        );
        if (!mounted) return;
        if (profile == null) {
          setState(() {
            _registering = false;
            _password.clear();
            _confirmPassword.clear();
          });
          _showError(
            'Te enviamos un correo para confirmar tu cuenta. '
            'Confírmalo antes de iniciar sesión.',
          );
          return;
        }
        widget.onContinue(profile);
      } else {
        final profile = await _repository.signIn(
          _email.text.trim(),
          _password.text,
        );
        if (mounted) widget.onContinue(profile);
      }
    } on AccountRepositoryException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError('No se pudo completar el acceso: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDateOfBirth() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dateOfBirth = selected;
      _dateOfBirthText.text =
          '${selected.day.toString().padLeft(2, '0')}/'
          '${selected.month.toString().padLeft(2, '0')}/'
          '${selected.year}';
    });
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Ingresa tu correo.';
    if (email.characters.length > 254) {
      return 'El correo excede la longitud permitida.';
    }
    final separator = email.indexOf('@');
    final localPart = separator < 0 ? '' : email.substring(0, separator);
    final domain = separator < 0 ? '' : email.substring(separator + 1);
    if (!_emailPattern.hasMatch(email) ||
        localPart.length > 64 ||
        domain.length > 253) {
      return 'Ingresa un correo válido.';
    }
    return null;
  }

  Future<void> _requestPasswordReset() async {
    final emailError = _validateEmail(_email.text);
    if (emailError != null) {
      _showError('Escribe un correo válido para enviarte el enlace.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.requestPasswordReset(_email.text.trim());
      if (mounted) {
        _showError(
          'Si existe una cuenta con ese correo, recibirás instrucciones para cambiar la contraseña.',
        );
      }
    } on AccountRepositoryException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  if (widget.initialError case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No se pudo restaurar la sesión: $error',
                      style: const TextStyle(
                        color: BioMedicaColors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
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
                                _label('Nombre'),
                                TextFormField(
                                  key: const ValueKey('registrationFirstName'),
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _maxNameLength,
                                  decoration: _decoration(
                                    'Ej. Valeria Mora',
                                    Icons.person_outline_rounded,
                                  ).copyWith(counterText: ''),
                                  validator: (value) {
                                    final name = value?.trim() ?? '';
                                    final nameLength = name.characters.length;
                                    if (nameLength < 2) {
                                      return 'Escribe tu nombre.';
                                    }
                                    if (nameLength > _maxNameLength) {
                                      return 'El nombre excede la longitud permitida.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _label('Apellidos'),
                                TextFormField(
                                  key: const ValueKey('registrationLastName'),
                                  controller: _lastName,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _maxLastNameLength,
                                  decoration: _decoration(
                                    'Ej. García López',
                                    Icons.badge_outlined,
                                  ).copyWith(counterText: ''),
                                  validator: (value) {
                                    final lastName = value?.trim() ?? '';
                                    if (lastName.characters.length < 2) {
                                      return 'Escribe tus apellidos.';
                                    }
                                    if (lastName.characters.length >
                                        _maxLastNameLength) {
                                      return 'Los apellidos exceden la longitud permitida.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _label('Fecha de nacimiento'),
                                TextFormField(
                                  key: const ValueKey(
                                    'registrationDateOfBirth',
                                  ),
                                  controller: _dateOfBirthText,
                                  readOnly: true,
                                  onTap: _pickDateOfBirth,
                                  decoration: _decoration(
                                    'Selecciona tu fecha de nacimiento',
                                    Icons.calendar_month_outlined,
                                  ),
                                  validator: (_) => _dateOfBirth == null
                                      ? 'Selecciona tu fecha de nacimiento.'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                _label('Padecimientos crónicos (opcional)'),
                                ..._chronicConditionOptions.map(
                                  (condition) => Material(
                                    color: Colors.transparent,
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      title: Text(condition),
                                      value: _chronicConditions.contains(
                                        condition,
                                      ),
                                      onChanged: (selected) => setState(() {
                                        if (selected == true) {
                                          _chronicConditions.add(condition);
                                        } else {
                                          _chronicConditions.remove(condition);
                                        }
                                      }),
                                    ),
                                  ),
                                ),
                                if (_chronicConditions.contains(
                                  _otherCondition,
                                )) ...[
                                  const SizedBox(height: 8),
                                  _label('¿Cuál padecimiento?'),
                                  TextFormField(
                                    controller: _otherConditionText,
                                    maxLength: 150,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: _decoration(
                                      'Escribe el padecimiento',
                                      Icons.edit_note_rounded,
                                    ).copyWith(counterText: ''),
                                  ),
                                ],
                                const SizedBox(height: 16),
                              ],
                              _label('Correo electrónico'),
                              TextFormField(
                                key: const ValueKey('accountEmail'),
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                maxLength: 254,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration(
                                  'tu@correo.com',
                                  Icons.mail_outline_rounded,
                                ).copyWith(counterText: ''),
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: 16),
                              _label('Contraseña'),
                              TextFormField(
                                key: const ValueKey('accountPassword'),
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
                                  final passwordLength =
                                      password.characters.length;
                                  // La contraseña debe tener entre 8 y 30 caracteres.
                                  if (passwordLength < 8) {
                                    return 'Usa al menos 8 caracteres.';
                                  }
                                  if (passwordLength > _maxPasswordLength) {
                                    return 'La contraseña excede la longitud permitida.';
                                  }
                                  return null;
                                },
                              ),
                              if (_registering) ...[
                                const SizedBox(height: 16),
                                _label('Confirmar contraseña'),
                                TextFormField(
                                  key: const ValueKey('confirmPassword'),
                                  controller: _confirmPassword,
                                  obscureText: true,
                                  maxLength: _maxPasswordLength,
                                  textInputAction: TextInputAction.done,
                                  decoration: _decoration(
                                    'Repite tu contraseña',
                                    Icons.lock_outline_rounded,
                                  ).copyWith(counterText: ''),
                                  validator: (value) {
                                    if ((value ?? '').isEmpty) {
                                      return 'Confirma tu contraseña.';
                                    }
                                    return value == _password.text
                                        ? null
                                        : 'Las contraseñas no coinciden.';
                                  },
                                ),
                              ] else
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : _requestPasswordReset,
                                    child: const Text(
                                      '¿Olvidaste tu contraseña?',
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
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
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _registering = !_registering,
                                  ),
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
                  const Text(
                    'Te enviaremos un correo para confirmar tu cuenta.',
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
