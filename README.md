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
- [Repositorio del proyecto en GitHub](https://github.com/vic0192/app-movil-integral)

Para usar otro backend:

```powershell
flutter run --dart-define=BIOMEDICA_API_URL=https://tu-api.example.com
```

La app consulta `GET /api/status` cada 30 segundos. Si la API no responde o no
tiene lecturas, presenta datos de muestra identificados como demostración. El
acceso y el registro siguen siendo locales; el turno mostrado es de muestra
mientras el backend no relacione turnos con una cuenta de paciente.

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
