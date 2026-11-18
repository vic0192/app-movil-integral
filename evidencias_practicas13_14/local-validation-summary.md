# Evidencia local — Prácticas 13 y 14

Fecha de ejecución: 2026-11-17
Entorno: Windows, Flutter 3.47.9 / Dart 3.13.7, Node.js 22.22.0, Java 17.

| Comando | Resultado | Tiempo |
|---|---:|---:|
| `flutter analyze` | Exit code 0; sin problemas | 26.26 s |
| `flutter test --reporter expanded` | Exit code 0; 95/95 pruebas aprobadas | 42.32 s |
| `npm test --prefix backend` | Exit code 0; 25/25 pruebas aprobadas | 15.69 s |
| `flutter build apk --debug` | Exit code 0 | incluido abajo |
| `.\android\gradlew.bat -p android :wear:assembleDebug --no-daemon` | Exit code 0 | incluido abajo |
| Builds Android + Wear OS | Ambos exitosos | 248.21 s |

Las ejecuciones usaron una API HTTP local controlada para los escenarios de
repositorio; no accedieron a datos clínicos ni servicios productivos. El daemon
Docker no estaba disponible, así que no se ejecutó una instancia real de
PostgreSQL/Supabase.

CI remoto: [GitHub Actions — run 44223004277, exitoso](https://github.com/vic0192/app-movil-integral/actions/runs/44223004277).
