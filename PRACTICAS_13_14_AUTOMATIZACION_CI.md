# Prácticas 13 y 14 — Automatización de pruebas y validación continua

**Proyecto:** BioMedica Flutter/Kotlin
**Fecha de ejecución:** 17 de noviembre de 2026
**Componentes evaluados:** captura Wear OS, cliente HTTP y persistencia de mediciones

## Alcance y riesgo elegido

Se automatizó el recorrido de una lectura de frecuencia cardiaca del reloj hasta
el historial del paciente. Los componentes críticos son: la interpretación y
validación de la lectura; `CoreApiClient` y `RelationalMeasurementRepository`;
y el guardado/consulta de las mediciones del paciente.

El riesgo elegido fue que una lectura incompleta, vencida o fuera de rango, una
sesión expirada o un servidor indisponible se aceptaran como un registro exitoso.
También se comprobó que la lectura se leyera de vuelta bajo la identidad del
paciente. Los valores opcionales que el reloj no mide se conservan como nulos.

## Pruebas y matriz AUT

| ID | Tipo | Verificación | Resultado |
|---|---|---|---|
| AUT-01 | Unitaria | Captura válida y conversión a medición | Aprobada |
| AUT-02 | Unitaria | Lectura incompleta y nombre vacío | Aprobada |
| AUT-03 | Unitaria | BPM/SpO₂ fuera de rango y lectura vencida | Aprobada |
| AUT-04 | Integración | Repositorio → cliente HTTP → API local; token, escritura e ID | Aprobada |
| AUT-05 | Integración | Sesión expirada y HTTP 503; no confirmar guardado | Aprobada |
| AUT-06 | Persistencia | Guardar y consultar de vuelta la medición del paciente | Aprobada |
| AUT-07 | CI | Workflow configurado para `push`, `pull_request` y ejecución manual | Aprobada localmente; ejecución remota ligada abajo |
| AUT-08 | CI | Análisis Dart, Flutter tests, backend y builds Android/Wear OS | Aprobada localmente; ejecución remota ligada abajo |

Las pruebas nuevas están en:

- `test/watch_capture_validation_test.dart` (7 pruebas unitarias).
- `test/watch_capture_api_integration_test.dart` (3 pruebas de autenticación,
  escritura y rechazo de datos no permitidos).
- `test/watch_capture_error_integration_test.dart` (1 prueba de fallo HTTP).
- `test/watch_measurement_readback_integration_test.dart` (1 prueba de lectura
  posterior a la persistencia).

Las pruebas de integración usan el `CoreApiClient` y el
`RelationalMeasurementRepository` reales contra un servidor HTTP local con
respuestas controladas. No se conectan a cuentas, datos clínicos ni servicios
productivos.

## Automatización y resultados

El workflow [`.github/workflows/flutter-kotlin-ci.yml`](.github/workflows/flutter-kotlin-ci.yml)
se ejecuta en cada push, pull request hacia `main` y manualmente. Tiene dos
trabajos independientes: análisis/pruebas/build de Flutter y Wear OS, y pruebas
del backend Node.js.

| Comando | Resultado | Tiempo |
|---|---:|---:|
| `flutter analyze` | Sin problemas | 26.26 s |
| `flutter test --reporter expanded` | 95/95 aprobadas, 0 fallidas | 42.32 s |
| `npm test --prefix backend` | 25/25 aprobadas, 0 fallidas | 15.69 s |
| `flutter build apk --debug` | APK del teléfono generado | incluido en build conjunto |
| `.\android\gradlew.bat -p android :wear:assembleDebug --no-daemon` | Build Wear OS exitoso | |
| Builds Android teléfono + Wear OS | Ambos exitosos | 248.21 s |

## Incidencias y correcciones

Durante la preparación, el primer test se lanzó fuera de la raíz Flutter y
terminó con `Test directory "test" not found`; se corrigió ejecutándolo desde
`biomedica_app`. La primera versión de los imports de pruebas usó separadores
Windows dentro de URI Dart y el analizador no encontró los paquetes; se
cambiaron a URI con `/`. El análisis completo también encontró cuatro retornos
de `Future` sin `await` dentro de `try` en los repositorios de cuenta. Se agregó
`await` en inicio de sesión/registro para que los errores asíncronos sí se
capturen y traduzcan. Después, el análisis completo y las 95 pruebas quedaron
verdes.

Gradle muestra avisos de compatibilidad/deprecación del plugin Kotlin/AGP, pero
los APK se construyeron correctamente. No se detectaron fallos nuevos en las
pruebas ejecutadas.

## Evidencia CI y limitaciones

- Evidencia local:
  [`local-validation-summary.md`](evidencias_practicas13_14/local-validation-summary.md).
- Ejecución GitHub Actions: **se completará al publicar el commit de esta
  práctica**; registrar aquí el enlace del run y su estado final.
- No había un dispositivo Android conectado ni el driver de virtualización
  requerido para iniciar el emulador Wear OS. La telemetría física del reloj no
  se simuló como una lectura real.
- `docker info` indicó que el daemon no está disponible. Por eso la persistencia
  se validó a través de la API local simulada y el repositorio real, no contra
  PostgreSQL/Supabase real. La prueba confirma el contrato de transporte y
  serialización, no el despliegue de la base ni sus políticas RLS.

## Conclusión

La automatización protege el flujo de mediciones frente a cambios futuros:
comprueba entradas válidas e inválidas, autenticación, errores del servicio y
lectura posterior del registro. El análisis detectó además una condición real:
sin `await`, los errores asíncronos escapaban de los bloques de traducción de
errores. La corrección y la repetición de la suite completa dan una base
reproducible para revisar la calidad antes de integrar cambios. El workflow
repite las comprobaciones en push y pull request, incluyendo los dos targets
Android, para detectar regresiones sin depender de un reloj conectado.
