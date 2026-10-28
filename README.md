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

Las pruebas del backend requieren Node.js 20 o superior:

```powershell
Set-Location backend
npm ci
npm test
```

## Acceso y roles

El acceso, los perfiles, las mediciones y los recordatorios usan Supabase Auth
y PostgreSQL con políticas RLS. Los reportes de malestares se guardan en Firestore
y se consultan mediante la API de Render, que verifica la sesión de Supabase y
aplica la identidad del paciente, administrador o médico asignado. Firestore
no se expone directamente a la app. Las cuentas nuevas empiezan como pacientes
y requieren confirmar el correo.

La app móvil necesita únicamente la clave publicable. Nunca incluyas una clave
`service_role` en la app, el JSON local ni el repositorio. Copia
[supabase.example.json](supabase.example.json) como `supabase.local.json`, pon la
URL y clave publicable de tu proyecto, y aplica la migración
[20261027000000_health_data.sql](supabase/migrations/20261027000000_health_data.sql)
desde el SQL Editor de Supabase. Configura los proveedores de correo para
exigir confirmación. En Authentication → URL Configuration, deja como Site URL
`https://app-biomedica-web.onrender.com/auth/confirmed` y agrega estas dos
Redirect URLs:

```text
https://app-biomedica-web.onrender.com/auth/confirmed
com.example.biomedica_app://login-callback/
```

La primera muestra la página segura de confirmación en Render y redirige el
resultado de Supabase a la app; la segunda permite volver directamente a la app
para restablecer contraseñas. La plantilla de confirmación debe conservar
`{{ .ConfirmationURL }}`. Android e iOS ya registran el esquema de callback.

En Render, configura `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en el servicio
`biomedica-api`, además de sus variables actuales `DATABASE_URL`,
`FIREBASE_SERVICE_ACCOUNT_JSON` y `JWT_SECRET`. La clave publicable también se
usa del lado del servidor para consultas sujetas al token del usuario; nunca
uses `service_role` en la app. El backend requiere esas variables para iniciar.

Ejecuta la app incluyendo ambos define necesarios:

```powershell
Copy-Item supabase.example.json supabase.local.json
# Edita supabase.local.json con los valores de tu proyecto
flutter run --dart-define-from-file=supabase.local.json `
  --dart-define=BIOMEDICA_CORE_API_URL=https://app-biomedica-web.onrender.com
```

Para registrar el primer administrador, crea y confirma su cuenta y luego
actualiza su rol desde el SQL Editor de Supabase, sustituyendo el UID por el de
esa cuenta. Comprueba que se afecte exactamente una fila:

```sql
UPDATE public.profiles
SET role = 'admin'
WHERE id = 'AUTH-USER-UUID'::uuid;
```

Los recordatorios se guardan por usuario en Supabase y se programan como
notificaciones locales al iniciar sesión y guardar cambios. El usuario debe
permitir las notificaciones en el teléfono; el ahorro de batería puede retrasar
los avisos. Las mediciones reales del reloj se guardan cuando el paciente toca
**Guardar medición**; las lecturas de demostración no se aceptan.

La API de Render y Firestore que se documentan abajo son componentes heredados
que siguen utilizándose para el estado/telemetría del dashboard y para
instalaciones previas; no son el almacenamiento activo de Auth, reportes,
mediciones ni recordatorios. Los datos históricos no se migran automáticamente.

Ejecuta las pruebas del formulario con:

```powershell
flutter test test\widget_test.dart
```

Para las evidencias, prueba correo vacío/mal formado, contraseñas fuera del
límite o que no coincidan, credenciales incorrectas y registro con confirmación
de correo en Supabase. En Logcat comprueba que no aparezcan las contraseñas.

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

Para configurar el servicio heredado de estado/telemetría de Render:

```powershell
flutter run --dart-define=BIOMEDICA_CORE_API_URL=https://tu-api.onrender.com
```

La API está en [backend/](backend/) y el blueprint de Render en
[render.yaml](render.yaml). En el dashboard de Render crea los servicios desde
el blueprint, configura `FIREBASE_SERVICE_ACCOUNT_JSON` en el servicio web con
una cuenta de servicio limitada al acceso de Firestore, y confirma que el
servicio pase `GET /health`. Render conecta PostgreSQL mediante `DATABASE_URL`
y genera `JWT_SECRET`. Nunca guardes claves privadas en el repositorio.

La base heredada crea `app_users`, `patient_assignments` y `measurements`.
Firebase/Firestore se conserva para compatibilidad con ese backend; los flujos
nuevos de reportes y mediciones usan Supabase.

Para inicializar el primer administrador en una instalación nueva, registra
una cuenta desde la app y cambia su rol desde la consola PostgreSQL de Render:

```sql
UPDATE app_users SET role = 'admin' WHERE email = 'admin@tu-dominio.com';
```

Verifica que la consulta afecte exactamente una cuenta. Después, el admin
promueve médicos y asigna pacientes desde la pestaña **Usuarios** (máximo 30
pacientes por médico).

#### Migración antigua Firebase → Render (no usar para la instalación Supabase)

La migración histórica siguiente solo corresponde al backend heredado de
Render. En esta integración nueva se acordó no migrar cuentas ni datos
existentes; no ejecutes estos scripts como parte de la puesta en marcha de
Supabase.

Antes de permitir nuevos registros, ejecuta una vez el importador en el Shell
del servicio de Render, donde ya están configurados `DATABASE_URL` y
`FIREBASE_SERVICE_ACCOUNT_JSON`:

```sh
node scripts/import_legacy_firebase_data.js
```

El importador conserva los UID históricos, roles y asignaciones; lleva las
mediciones válidas a PostgreSQL y deja intactos los reportes en Firestore. No
es posible obtener contraseñas originales desde Firebase. Las cuentas
importadas reciben hashes de contraseñas aleatorias inutilizables; verifica la
identidad de cada persona y asigna una nueva contraseña desde una terminal
administrativa segura:

```powershell
node scripts/set_user_password.js usuario@dominio.com
```

El script no muestra la contraseña en pantalla y no cambia el rol. Haz respaldo
de Firestore y PostgreSQL antes de migrar. Si una cuenta con el mismo correo ya
existe en PostgreSQL, detén la migración y resuelve el conflicto antes de
reintentar; no se sobrescriben cuentas existentes.

### Datos del reloj y límites clínicos

El companion `:wear` solicita permiso `BODY_SENSORS` y transmite el pulso
obtenido con `Sensor.TYPE_HEART_RATE`. Es el dato implementado para Galaxy
Watch. No todos los relojes exponen SpO₂ o temperatura; solo se guardan si una
fuente real compatible los proporciona. Las lecturas simuladas no se pueden
guardar.

La app conserva valores y fechas, pero **no genera diagnósticos, alertas
clínicas ni recomendaciones médicas**. Los límites de captura son validaciones
técnicas, no umbrales clínicos.

## Práctica 8: evaluación de calidad por caja negra

El reporte está en [HTML](Practica_8_Evaluacion_Caja_Negra.html) y
[PDF](Practica_8_Evaluacion_Caja_Negra.pdf). Documenta el inventario funcional,
18 requisitos identificados, entradas, restricciones, resultados esperados,
casos de prueba, evidencias disponibles y pendientes de verificación. Las
pruebas locales no sustituyen las comprobaciones contra PostgreSQL/Render,
Firestore y un Galaxy Watch real. El checklist de migración y pruebas está en
[CHECKLIST_VALIDACIONES_PRACTICA_8.md](CHECKLIST_VALIDACIONES_PRACTICA_8.md).

## Versionamiento

La versión objetivo es `1.3.0+5` en `pubspec.yaml`. Configura
`supabase.local.json` al compilar para que la APK conecte Auth/datos con
Supabase y los reportes con la API de Render:

```powershell
flutter build apk --release --build-name 1.3.0 --build-number 5 `
  --dart-define-from-file=supabase.local.json `
  --dart-define=BIOMEDICA_CORE_API_URL=https://app-biomedica-web.onrender.com
```

La APK release está firmada con la clave de
depuración del proyecto y es para pruebas; Google Play requiere una clave de
producción.

## Wear OS y emuladores

Android incluye el companion nativo `:wear`, que solicita permiso
`BODY_SENSORS` y transmite las lecturas del sensor de pulso. No inventa valores
si no existe sensor o permiso. Para que funcione, teléfono y reloj deben estar
emparejados y tener instalada su aplicación.

1. Inicia los AVD `Medium_Phone` y `Wear_OS_Large_Round`.
2. En Android Studio, abre **Device Manager** y usa el menú del AVD del teléfono
   para emparejarlo con el AVD Wear OS.
3. Instala la app Flutter en el teléfono con `flutter run -d <id-del-teléfono>`.
4. Desde `biomedica_app\android`, instala el companion del reloj:

   ```powershell
   .\gradlew.bat :wear:installDebug
   ```

5. Abre **BioMedica Watch**, concede permiso al sensor y deja la app del
   teléfono abierta. Un emulador sin sensor no puede validar lecturas reales;
   la prueba de captura requiere el Galaxy Watch.

## APK de depuración

```powershell
flutter build apk --debug
```

El archivo generado queda en `build/app/outputs/flutter-apk/app-debug.apk`.
El companion Wear OS se compila con
`.\gradlew.bat :wear:assembleDebug` desde `biomedica_app\android`.
