# BioMedica Paciente

Aplicación Flutter para pacientes. La capa `screens` contiene las vistas y sus
flujos de interacción; `services`, `data` y `ble` aíslan la comunicación con la
plataforma, la API y los wearables; `widgets` contiene componentes visuales
reutilizables y sin estado propio.

Los formularios, el shell del paciente y el proceso de vinculación son
`StatefulWidget` porque mantienen datos editables, navegación o actividad
asíncrona. Los indicadores vitales, tarjetas de historial y hero del turno son
`StatelessWidget`; reciben sus valores desde el estado dueño.

## Pantallas y diseño

- Acceso y registro: formularios lineales, limpios y centrados en la tarea.
- Vinculación: diálogo/modal con tarjeta central para búsqueda, conexión y
  estado BLE.
- Inicio: dashboard vertical con tarjetas e indicadores circulares para
  frecuencia cardiaca, SpO₂ y temperatura; incluye actividad, wearable y turno.
- Historial: lista vertical de lecturas y gráfica.
- Mi turno: estado focalizado con número destacado, estado y progreso visual.

Las vistas usan desplazamiento, `LayoutBuilder`, `MediaQuery` y un ancho máximo
de contenido para adaptarse a teléfonos compactos (360 × 640), estándar
(375 × 812) y grandes (414 × 896), con orientación vertical como referencia.

## Widget de inicio Android

En Inicio, toca **Añadir widget** y confirma la solicitud del launcher. También
puedes agregarlo desde el selector de widgets del teléfono. Muestra BPM, SpO₂,
temperatura, hora de actualización y distingue los datos de demostración. Tocar
el widget abre BioMedica. Los datos se actualizan al sincronizar la app; no se
actualizan si Android detiene la app y no hay sincronización nueva.

La integración del widget del sistema es nativa de Android. iOS requiere una
extensión WidgetKit independiente.

## Ejecutar y validar

```powershell
flutter pub get
flutter run
flutter analyze
flutter test
```

## Práctica 5: acceso seguro

La pantalla de acceso aplica validaciones locales para el usuario (no vacío ni
solo espacios, máximo 30 caracteres) y la contraseña (mínimo 8 y máximo 30
caracteres). La contraseña se muestra oculta. Si las credenciales simuladas no
coinciden, presenta un mensaje genérico y no registra usuario ni contraseña.

Para probar el acceso simulado usa el usuario `paciente` y la contraseña
`BioMedica2026`. Son datos fijos para esta práctica; no representan una cuenta
real y no deben reutilizarse en producción. El acceso no autentica contra un
servidor.

Ejecuta las pruebas del formulario con:

```powershell
flutter test test\widget_test.dart
```

Para las evidencias, abre el proyecto en Android Studio y captura la pantalla
de acceso, un intento con usuario vacío o solo espacios (debe mostrar el error
de validación), y Logcat después de intentar el acceso válido e inválido. En
Logcat selecciona el proceso de BioMedica y comprueba que no aparezcan los
valores introducidos como usuario o contraseña.

Respuestas breves:

- **¿Por qué no deben registrarse contraseñas en Logcat?** Los registros pueden
  quedar accesibles para depuración, copias o herramientas de diagnóstico; una
  contraseña expuesta permitiría tomar control de la cuenta.
- **¿Qué diferencia existe entre ocultar una contraseña y cifrarla?** Ocultarla
  solo enmascara los caracteres en pantalla. Cifrarla transforma los datos para
  que no se lean sin la clave correspondiente; la máscara visual no protege su
  almacenamiento o transmisión.
- **¿Por qué la validación del lado del cliente no es suficiente?** El usuario
  puede modificar o eludir la app y enviar solicitudes directamente. El
  servidor debe validar y autenticar cada solicitud por sí mismo.

## Entregables de la práctica

- [Reporte en PDF](Practica_5_Reporte_AccesoSeguro.pdf)
- [Reporte en HTML](Practica_5_Reporte_AccesoSeguro.html)
- [Capturas del emulador y Logcat](practica5_evidencias/)
- [Repositorio privado del proyecto en GitHub](https://github.com/vic0192/biomedica-integral-entregables)

Para usar otro backend:

```powershell
flutter run --dart-define=BIOMEDICA_API_URL=https://tu-api.example.com
```

La app consulta `GET /api/status` cada 30 segundos. Si la API no responde o no
tiene lecturas, presenta datos de muestra identificados como demostración. El
acceso y el registro siguen siendo locales; el turno mostrado es de muestra
mientras el backend no relacione turnos con una cuenta de paciente.

## Práctica: Firestore y reportes de equipo

La pestaña **Reportes** permite registrar, consultar, actualizar y eliminar
reportes de equipo en la colección `reportes`. Cada documento contiene su ID
Firestore (por ejemplo, `REP001`), `equipment`, `description`, `priority`,
`ownerUid`, `createdAt` y `updatedAt`. Equipo y descripción son obligatorios;
la prioridad se limita a `Baja`, `Media` o `Alta`. Los reportes están asociados
al UID de una sesión anónima de Firebase y cada usuario solo puede acceder a
los suyos.

### Configurar el proyecto Firebase

BioMedica inicializa el proyecto `iotprueba-fc74f` con la configuración web
proporcionada en `lib\firebase_options.dart`; no se añadió la configuración
web al código Android nativo. En Firebase Console, activa **Authentication →
Sign-in method → Anonymous** y **Cloud Firestore**. Registra también la app
Android con el `applicationId` de `android\app\build.gradle.kts` mediante
FlutterFire CLI antes de publicar o distribuir fuera de este entorno probado.
La clave web es un identificador público de Firebase, no una
contraseña: aplica restricciones de API en Google Cloud y mantén las reglas
delimitadas por UID.

Selecciona el proyecto correcto y publica `firestore.rules` con Firebase CLI:

   ```powershell
   firebase use iotprueba-fc74f
   firebase deploy --only firestore:rules
   ```

Para sustituir la configuración por opciones nativas de Android y web de
FlutterFire, registra ambas apps y vuelve a ejecutar:

   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

   Selecciona el proyecto Firebase y las plataformas requeridas; integra las
   opciones generadas en `main.dart`. No agregues claves de servidor ni
   credenciales privadas a Git.

Ejecuta `flutter pub get` y `flutter run`. Inicia sesión en BioMedica,
   abre **Reportes** y copia el UID de pruebas que aparece debajo del aviso.
   Si el listado no carga, confirma que Anonymous esté habilitado y que las
   reglas publicadas coincidan con `firestore.rules`.

Cada documento necesita `ownerUid`, `equipment`, `description`, `priority`,
`createdAt` y `updatedAt`. Para crear un documento manual, usa el UID de
pruebas mostrado en **Reportes**, equipo y descripción no vacíos, una prioridad
permitida y fechas de tipo timestamp. Las reglas impiden lecturas o
modificaciones entre usuarios y validan el esquema. No uses reglas abiertas en
una aplicación real.

### Pruebas de interfaz

```powershell
flutter test test\reports_screen_test.dart
```

Los casos de TC01 a TC08 se mantienen en
`test\reports_screen_test.dart`. Los widget tests usan un repositorio falso
para pruebas repetibles. Se comprobó en el emulador Android que Firestore
crea, actualiza y elimina reportes, encuentra el estado vacío de REP999 y
conserva REP008 después de cerrar y abrir la app. TC03 y TC07 aún no se han
ejecutado contra Firestore real; el test de TC07 solo simula el error.

La consulta de reportes filtra por UID y ordena en el dispositivo para evitar
depender de un índice compuesto. Si Firebase Console reporta otro error,
confirma que Anonymous esté habilitado, que Firestore esté activo y que
`firestore.rules` esté publicado en `iotprueba-fc74f`.

El reporte y las capturas están en [reporte_practica_firestore.html](reporte_practica_firestore.html)
y [practica_firestore_evidencias](practica_firestore_evidencias/). La captura
compartida de Firebase Console muestra una fila `REP001`, pero el documento
seleccionado tiene un ID automático y campos del esquema anterior; por sí sola
no prueba que el segundo insert se rechazara sin sobrescribir. `firestore.rules`
está actualizado en el repositorio, pero todavía debe publicarse con Firebase
CLI y comprobarse en el proyecto; no des por validado el aislamiento de datos
antes de ese paso.

## Base de datos relacional planeada

El entregable contempla PostgreSQL como base relacional del backend para los
datos estructurados compartidos entre la app, el sistema web y el panel de
turnos. La app móvil accederá a PostgreSQL mediante una API autenticada; no se
deben incluir credenciales SQL en Flutter. Esta conexión aún no está
implementada. Los reportes de equipo de la versión actual continúan usando
Cloud Firestore, como se describe arriba.

## Versionamiento

La versión Android se declara en `pubspec.yaml`. El hito `1.1.0+2` agrega el
flujo de reportes Firestore y sus pruebas. Se registra una corrección verificada:
la consulta dejó de requerir un índice compuesto al ordenar los resultados
localmente. Los casos TC03 (duplicado real) y TC07 (pérdida real de conexión)
siguen pendientes de comprobación contra el servicio. El historial y la
cantidad de correcciones se documentan sin crear versiones o fallos ficticios.

## Wear OS y emuladores

Android incluye la app nativa `:wear`, que publica lecturas de muestra cada tres
segundos por Wearable Data Layer. BioMedica recibe esas lecturas en la pantalla
Inicio cuando el AVD Wear OS está emparejado y la app del teléfono está abierta.
Los datos de BioWatch están marcados como demostración y no provienen de un
sensor biométrico.

1. Inicia los AVD `Medium_Phone` y `Wear_OS_Large_Round`.
2. En Android Studio, abre **Device Manager** y usa el menú del AVD del teléfono
   para emparejarlo con el AVD Wear OS.
3. Instala la app Flutter en el teléfono con `flutter run -d <id-del-teléfono>`.
4. Desde `biomedica_app\android`, instala el companion del reloj:

   ```powershell
   .\gradlew.bat :wear:installDebug
   ```

5. Abre **BioMedica Watch** en el reloj y deja Inicio abierto en el teléfono.
   La tarjeta de Dispositivo mostrará **BioWatch del emulador conectado** al
   recibir los datos.

## APK de depuración

```powershell
flutter build apk --debug
```

El archivo generado queda en `build/app/outputs/flutter-apk/app-debug.apk`.
El companion Wear OS se compila con
`.\gradlew.bat :wear:assembleDebug` desde `biomedica_app\android`.
