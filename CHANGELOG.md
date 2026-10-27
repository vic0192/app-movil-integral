# Historial de versiones

## 1.3.0+5 — 2026-10-22

- Migra cuentas, login, perfiles, roles, asignaciones y mediciones de Firebase a PostgreSQL mediante una API Node.js desplegable en Render.
- Almacena contraseñas con scrypt, emite JWT y conserva el token en almacenamiento seguro del dispositivo; el servidor verifica rol y permisos en cada solicitud.
- Mantiene los reportes en Firestore, ahora accedidos exclusivamente por el backend; las reglas niegan acceso directo desde clientes móviles.
- Añade un importador que conserva los UID, roles y asignaciones existentes, migra mediciones válidas y deja intactos los reportes. Las contraseñas requieren restablecimiento verificado por un administrador.
- Añade migración SQL, blueprint de Render y pruebas del backend.
- Validación local al 23/10/2026: `flutter analyze` limpio, 52 pruebas Flutter, 6 pruebas del backend y auditoría npm de producción sin vulnerabilidades. Render/PostgreSQL, Firestore desplegado y reloj físico aún no probados.
- Pendiente: configurar credenciales del servicio en Render, ejecutar la migración, desplegar las reglas y validar la URL de API contra los tres roles.

## 1.2.0+4 — 2026-10-22

- Reemplaza el acceso simulado por Firebase Authentication (correo y contraseña) y crea perfiles seguros de paciente.
- Añade roles paciente/médico/administrador, asignación de pacientes desde el panel del administrador y filtros de reportes por rol.
- Incorpora registros inmutables en Firestore para lecturas del reloj, con pulso, hora, fuente y dispositivo; SpO₂/temperatura son opcionales.
- Sustituye datos simulados del companion Wear OS por lecturas del sensor de pulso y permiso del sistema; los datos de muestra no se guardan.
- Evita enviar biometría a la API externa; el paciente guarda una lectura reciente explícitamente en Firestore.
- Actualiza reglas para cuentas, reportes, asignaciones y mediciones; el despliegue de reglas y Firebase Android aún requiere configuración externa.
- No genera diagnósticos ni recomendaciones clínicas; los límites aplicados son validaciones técnicas, no umbrales clínicos.
- Validación local: `flutter analyze` y 46 pruebas automatizadas aprobadas. Falta probar cuentas/roles en Firebase desplegado y un Galaxy Watch físico.

## 1.1.1+3 — 2026-10-20

- Unifica las validaciones del formulario y del repositorio para IDs, equipo, descripción y prioridad de reportes.
- Rechaza IDs de más de 100 caracteres y evita que validaciones del cliente se omitan llamando directamente al repositorio.
- Valida formato y longitudes de correo en el registro; limita el nombre a 100 caracteres y aclara que el registro es simulado.
- Endurece las reglas de Firestore para rechazar campos vacíos y exigir marcas de tiempo del servidor al crear/actualizar.
- Agrega pruebas de límites, entradas inválidas y validación del repositorio antes de acceder a Firebase.
- Validación: `flutter analyze` sin incidencias y 34 pruebas focalizadas aprobadas; APK release generada.
- **Pendiente:** verificar reglas publicadas, permisos entre usuarios y operación de la APK en un dispositivo.

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
