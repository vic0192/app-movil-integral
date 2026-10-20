# Historial de versiones

## 1.1.0+2 — 2026-10-20

- Agrega reportes de equipo en Cloud Firestore con alta, consulta, actualización y eliminación.
- Agrega validación de campos, manejo de IDs solicitados y pruebas de interfaz/repositorio.
- Documenta PostgreSQL como base relacional planeada para el backend; la app aún no se conecta a ella.
- **Correcciones verificadas acumuladas: 1.** Se eliminó la dependencia de un índice compuesto de Firestore ordenando los resultados en el dispositivo.
- **Pendiente:** verificar el rechazo del ID duplicado contra Firestore real y simular pérdida real de conexión.
- Verificación: `flutter analyze`, 18 pruebas automatizadas y `flutter build apk --release`.

## 1.0.0+1 — línea base

- Línea base del prototipo móvil y el entregable 1, conservada en el commit inicial del repositorio.
- Correcciones verificadas registradas para esta línea base: 0.
