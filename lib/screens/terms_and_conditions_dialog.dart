import 'package:flutter/material.dart';

import '../data/terms_policy.dart';

Future<bool> showTermsAcceptanceDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => const TermsAndConditionsDialog(),
    ) ??
    false;

class TermsAndConditionsDialog extends StatefulWidget {
  const TermsAndConditionsDialog({super.key});

  @override
  State<TermsAndConditionsDialog> createState() =>
      _TermsAndConditionsDialogState();
}

class _TermsAndConditionsDialogState extends State<TermsAndConditionsDialog> {
  final _scrollController = ScrollController();
  bool _readToEnd = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkReadProgress);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_checkReadProgress)
      ..dispose();
    super.dispose();
  }

  void _checkReadProgress() {
    if (!_readToEnd &&
        _scrollController.hasClients &&
        _scrollController.position.extentAfter <= 24) {
      setState(() => _readToEnd = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return AlertDialog(
      title: const Text('Términos y condiciones de BioMedica'),
      content: SizedBox(
        width: 520,
        height: maxHeight,
        child: Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 12),
                  child: const _TermsContent(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _accepted,
              onChanged: _readToEnd
                  ? (value) => setState(() => _accepted = value == true)
                  : null,
              title: Text(
                _readToEnd
                    ? 'Confirmo que leí y acepto estos términos y el tratamiento de mis datos de salud.'
                    : 'Desplázate hasta el final para habilitar la aceptación.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          child: const Text('Aceptar y volver'),
        ),
      ],
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Versión $currentTermsVersion · Vigentes desde el 27 de octubre de 2026',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 16),
      _Section(
        title: '1. Aceptación y alcance',
        body:
            'Estos términos regulan el uso de BioMedica, una aplicación de '
            'seguimiento personal de salud. Al crear una cuenta confirmas que '
            'leíste y aceptas estas condiciones, incluido el tratamiento de '
            'datos personales y de salud descrito aquí. Si no estás de acuerdo, '
            'no crees una cuenta ni uses las funciones que requieren acceso.',
      ),
      _Section(
        title: '2. Funciones y finalidad',
        body:
            'BioMedica permite consultar y registrar mediciones, vincular '
            'dispositivos compatibles, organizar recordatorios de medicación '
            'y medición, y crear reportes de malestares. La información se '
            'ofrece para ayudarte a organizar y consultar tus propios datos '
            'de salud y, cuando corresponda, facilitar su consulta por personal '
            'autorizado asignado a tu atención.',
      ),
      _Section(
        title: '3. No es un servicio médico ni de emergencia',
        body:
            'BioMedica no diagnostica enfermedades, no prescribe ni modifica '
            'tratamientos, y no sustituye la valoración de un profesional de '
            'salud. Las mediciones de teléfonos y dispositivos pueden ser '
            'inexactas, incompletas o retrasarse. No uses la aplicación para '
            'decidir por tu cuenta suspender medicamentos o retrasar atención. '
            'Ante síntomas graves o una emergencia, contacta inmediatamente '
            'a los servicios de emergencia de tu localidad o a un profesional.',
      ),
      _Section(
        title: '4. Cuenta y datos proporcionados',
        body:
            'Debes proporcionar datos correctos y mantener actualizada la '
            'información que registres. Eres responsable de proteger tu '
            'contraseña, cerrar sesión en dispositivos compartidos y avisar '
            'al administrador si sospechas un acceso no autorizado. No uses '
            'la cuenta de otra persona ni ingreses datos de terceros sin '
            'autorización. Si eres menor de edad, usa el servicio con la '
            'autorización y supervisión de tu madre, padre o tutor.',
      ),
      _Section(
        title: '5. Información personal y de salud',
        body:
            'Para operar la aplicación se pueden tratar tu nombre, correo, '
            'fecha de nacimiento, padecimientos que declares, ritmo cardiaco, '
            'oxigenación, temperatura cuando el dispositivo la proporcione, '
            'fechas de medición, dispositivo de origen, recordatorios, '
            'malestares, descripciones, prioridades de reportes y datos '
            'técnicos necesarios para la conexión. Autorizas expresamente su '
            'tratamiento para autenticarte, mostrar tus registros, generar '
            'recordatorios, atender reportes y prestar las funciones que '
            'solicites; no se venden para publicidad. Las cuentas autorizadas '
            'de profesionales solo pueden consultar información de pacientes '
            'que tengan asignados conforme a la configuración del servicio.',
      ),
      _Section(
        title: '6. Almacenamiento y proveedores',
        body:
            'La aplicación usa Supabase para autenticación y datos relacionales, '
            'y servicios de Render y Firebase/Firestore para componentes de '
            'la API y reportes. La comunicación con dispositivos puede usar '
            'Bluetooth y los permisos del sistema operativo. Estos proveedores '
            'procesan datos para prestar el servicio de acuerdo con sus '
            'funciones y configuraciones. Ningún sistema conectado a Internet '
            'puede garantizar disponibilidad o seguridad absoluta.',
      ),
      _Section(
        title: '7. Permisos, dispositivos y notificaciones',
        body:
            'Bluetooth, sensores y notificaciones requieren permisos del '
            'dispositivo. Puedes desactivarlos desde los ajustes del sistema, '
            'pero algunas funciones dejarán de operar. El ahorro de batería, '
            'la falta de conexión, las restricciones del fabricante o la '
            'desinstalación pueden impedir o retrasar recordatorios. La app '
            'no garantiza que una notificación llegue a una hora determinada; '
            'mantén tus propios medios de control de tratamientos.',
      ),
      _Section(
        title: '8. Uso permitido y disponibilidad',
        body:
            'Usa BioMedica de manera lícita y no intentes acceder a cuentas, '
            'datos o sistemas ajenos, interferir con el servicio, cargar '
            'contenido malicioso o eludir controles de seguridad. Las funciones '
            'pueden cambiar, suspenderse o no estar disponibles por mantenimiento, '
            'fallos de red, dispositivos incompatibles o servicios de terceros.',
      ),
      _Section(
        title: '9. Conservación y solicitudes',
        body:
            'Los datos se conservan mientras sean necesarios para prestar el '
            'servicio y mantener la cuenta, sujetos a obligaciones aplicables '
            'y copias de respaldo de los proveedores. La eliminación de la '
            'cuenta y el ejercicio de derechos de acceso, rectificación, '
            'cancelación u oposición, cuando procedan, pueden requerir '
            'asistencia del administrador de la plataforma. Contacta al '
            'administrador que te proporcionó el acceso para presentar la '
            'solicitud; algunas copias de respaldo pueden conservarse durante '
            'el ciclo técnico de eliminación o por obligaciones legales.',
      ),
      _Section(
        title: '10. Propiedad intelectual y cambios',
        body:
            'La aplicación, su diseño y sus materiales pertenecen a sus '
            'titulares o licenciantes y no se transfieren al usuario. Podemos '
            'actualizar funciones o estos términos para reflejar cambios '
            'técnicos, legales o del servicio. Si una nueva versión requiere '
            'consentimiento, se solicitará nuevamente antes de continuar '
            'usando la función correspondiente.',
      ),
      _Section(
        title: '11. Responsabilidad',
        body:
            'En la medida permitida por la legislación aplicable, BioMedica '
            'se proporciona como herramienta de apoyo y no garantiza que las '
            'mediciones, sincronizaciones, alertas o reportes estén siempre '
            'disponibles o libres de errores. Nada en estos términos limita '
            'derechos irrenunciables del consumidor o responsabilidades que '
            'la ley no permita excluir.',
      ),
      _Section(
        title: '12. Legislación y contacto',
        body:
            'Estos términos se interpretan conforme a la legislación aplicable, '
            'sin limitar los derechos que te correspondan en tu lugar de '
            'residencia. Para consultas, correcciones o solicitudes sobre tu '
            'cuenta y tus datos, contacta al administrador de la plataforma '
            'BioMedica que te proporcionó el acceso.',
      ),
      SizedBox(height: 12),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(body),
      ],
    ),
  );
}
