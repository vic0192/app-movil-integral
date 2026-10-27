# Checklist de validaciones de BioMedica

**Versión a probar:** 1.3.0+5  
**APK:** `BioMedica-v1.3.0.apk`  
**Fecha de última ejecución automatizada:** 23/10/2026  
**Dispositivo / Android:** No se ejecutaron pruebas de hardware en esta sesión.

En las tablas, `[x]` indica que el caso correspondiente se ejecutó en pruebas
automatizadas locales o con un repositorio simulado; no significa que se haya
probado en Render, PostgreSQL, Firestore desplegado o un dispositivo físico.
`[~]` indica cobertura parcial y `[ ]` indica que no hay evidencia de ejecución.
Los casos sin evidencia ejecutada permanecen pendientes.

## Resultado automatizado del código

- [x] `flutter analyze` sin errores.
- [x] Pruebas de límites y validaciones de acceso/registro.
- [x] Pruebas de límites y validaciones del formulario y repositorio de reportes.
- [x] Suite Flutter completa repetida: 52 pruebas aprobadas.
- [x] API backend repetida: 6 pruebas aprobadas y `npm audit --omit=dev` sin vulnerabilidades.
- [x] Validación automatizada de lecturas reales y rechazo de fuente simulada.
- [x] Auditoría de dependencias de producción repetida: 0 vulnerabilidades.
- [ ] API de Render y PostgreSQL desplegados; `GET /health` devuelve `ok`.
- [ ] Reglas de Firestore desplegadas para bloquear acceso directo desde clientes.
- [ ] Integración comprobada con usuarios y datos de producción.

## Acceso y registro

| Hecho | Caso | Resultado esperado | Resultado observado / evidencia |
|---|---|---|---|
| [x] | Iniciar sesión con correo vacío o compuesto por espacios. | Muestra «Ingresa tu correo» y no abre Inicio. | Prueba widget local; backend real no consultado. |
| [x] | Ingresar correo de más de 254 caracteres. | Limita o rechaza la entrada; no inicia sesión. | Prueba widget local; backend real no consultado. |
| [x] | Iniciar sesión con contraseña de 7 caracteres. | Muestra el error de mínimo 8 y no abre Inicio. | Prueba widget local aprobada. |
| [x] | Iniciar sesión con contraseña de 31 caracteres. | Rechaza el exceso y no abre Inicio. | Prueba widget local aprobada. |
| [x] | Iniciar sesión con credenciales incorrectas. | Error genérico; no entra y no revela qué dato falló. | Widget con repositorio simulado; falta repetir en la API desplegada. |
| [x] | Mostrar y volver a ocultar la contraseña. | Alterna la máscara sin borrar el valor. | Prueba widget local añadida y aprobada en esta ejecución. |
| [x] | Registro: correo `nombre@`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: correo `@dominio.com`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: correo `nombre@dominio`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: correo con espacios, por ejemplo `nombre con espacio@dominio.com`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: dominio inicia con guion, por ejemplo `nombre@-dominio.com`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: dominio con etiquetas vacías, por ejemplo `nombre@dominio..com`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: parte local con puntos consecutivos, por ejemplo `nombre..apellido@dominio.com`. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: parte local de más de 64 caracteres. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registro: etiqueta de dominio de más de 63 caracteres. | Muestra «Ingresa un correo válido» y no continúa. | Prueba widget local aprobada. |
| [x] | Registrar con nombre vacío o de menos de 3 caracteres. | Rechaza el nombre y no continúa. | Pruebas widget locales cubren campo vacío y nombre de 2 caracteres. |
| [x] | Registrar con nombre de más de 100 caracteres. | Rechaza el nombre y no continúa. | Prueba widget local aprobada. |
| [~] | Registrar con correo válido, nombre de 3–100 caracteres y contraseña de 8–30. | PostgreSQL crea una cuenta nueva con rol paciente; contraseña guardada como hash. | El formulario con repositorio simulado acepta; no se creó cuenta en PostgreSQL. |
| [x] | Repetir registro con el mismo correo. | API rechaza duplicado sin modificar la cuenta previa. | Prueba HTTP aprobada con base de datos simulada; falta confirmar contra PostgreSQL real. |
| [x] | Cerrar sesión y volver a abrir la app con sesión activa. | Token se restaura del almacenamiento seguro y perfil se consulta a la API. | Cliente HTTP con almacén simulado; almacenamiento del dispositivo y API desplegada pendientes. |

## Reportes y reglas de negocio

| Hecho | Caso | Resultado esperado | Resultado observado / evidencia |
|---|---|---|---|
| [x] | Crear un reporte con ID opcional, equipo/descripción no vacíos y prioridad permitida. | Crea un único reporte, asigna ID y muestra los valores guardados. | Widget automatizado con repositorio simulado; no Firestore real. |
| [x] | Guardar equipo o descripción vacíos o con solo espacios. | Se muestra el error correspondiente; no se crea documento. | Widget automatizado con repositorio simulado. |
| [x] | Guardar equipo de 100 y 101 caracteres; descripción de 500 y 501 caracteres. | Acepta el límite exacto y rechaza el carácter excedente. | Validación de modelo y límite máximo en widget; no escritura Firestore real. |
| [x] | Intentar ID de más de 100 caracteres o con `/`. | Informa el error y no crea ni sobrescribe documentos. | Validación automática; no Firestore real. |
| [x] | Elegir prioridades válidas y enviar una prioridad no permitida. | UI ofrece solo las tres opciones y la API rechaza valores distintos. | Prueba de catálogo/validador local; API de Render pendiente. |
| [x] | Crear un ID duplicado. | Se rechaza sin cambiar el reporte anterior. | Prueba con repositorio simulado; no Firestore real. |
| [~] | Buscar un ID existente e inexistente. | Muestra el documento correcto o el estado vacío sin excepción. | Suite cubre ID inexistente; falta caso positivo de búsqueda en ejecución actual. |
| [x] | Editar un reporte. | Conserva ID y `createdAt`; cambia datos permitidos y actualiza `updatedAt`. | Widget con repositorio simulado; marcas de tiempo no probadas en servicio real. |
| [~] | Cancelar y confirmar la eliminación. | Cancelar conserva el reporte; confirmar lo elimina. | Suite automatiza confirmación; cancelación no fue verificada. |
| [ ] | Eliminar un ID que no existe. | Informa el error y no afecta otros documentos. | Sin caso automatizado en esta ejecución. |
| [x] | Recrear la pantalla después de una operación. | El reporte simulado continúa visible tras recrear la pantalla. | Prueba con fake; no confirma persistencia real en Firestore. |
| [x] | Simular un fallo de conexión al guardar. | No presenta falso éxito y muestra el error. | TC07 usa error simulado; no es una desconexión real. |

## Mediciones del reloj

| Hecho | Caso | Resultado esperado | Resultado observado / evidencia |
|---|---|---|---|
| [ ] | Abrir el companion en Galaxy Watch y conceder permiso del sensor. | Muestra una lectura real de pulso; no inventa datos si el permiso falta. | |
| [ ] | Guardar una lectura reciente del reloj. | Crea un registro en PostgreSQL `measurements` con usuario, fecha, dispositivo, fuente y BPM. | |
| [x] | Validar fuente de demostración y lectura vencida en el modelo/repositorio. | Rechaza datos simulados o vencidos antes de guardar. | Prueba automatizada local; no es una medición física del reloj. |
| [ ] | Cerrar y abrir sesión y consultar mediciones. | Solo muestra mediciones del paciente autenticado según permisos de la API. | |
| [ ] | Verificar SpO₂ o temperatura en el modelo de reloj disponible. | Guarda solo campos proporcionados por un sensor compatible; si no, quedan vacíos. | |
| [ ] | Intentar modificar o borrar una medición desde la app. | La medición es inmutable; solo admin/doctor consultan según reglas. | |
| [x] | Revisar el código y textos principales respecto a diagnósticos. | No genera diagnósticos ni recomendaciones clínicas. | Verificación estática del alcance documentado; no es validación clínica. |

## Permisos y build

| Hecho | Caso | Resultado esperado | Resultado observado / evidencia |
|---|---|---|---|
| [ ] | Desplegar reglas de Firestore denegando acceso directo desde clientes. | El backend Admin SDK conserva acceso a reportes; clientes no pueden leer/escribir Firestore directamente. | |
| [ ] | Consultar/editar/eliminar reportes con el UID propietario. | Operaciones permitidas solo sobre sus reportes; datos almacenados en Firestore. | |
| [ ] | Intentar consultar/modificar datos ajenos sin sesión o con token inválido. | API responde 401/403 y no expone ni modifica datos ajenos. | |
| [ ] | Promover un usuario a médico/admin y asignar pacientes con admin. | Cambios persisten en PostgreSQL; médico ve solo asignados y admin administra usuarios. | |
| [ ] | Acceder a pacientes no asignados con cuenta médica. | API deniega lectura aunque se manipule la solicitud del cliente. | |
| [ ] | Instalar `BioMedica-v1.3.0.apk` sobre la versión anterior. | Instala/actualiza correctamente, muestra versión 1.3.0 y abre Inicio. | Pendiente: requiere API configurada y dispositivo Android. |

La APK release está firmada con la clave de depuración configurada en el
proyecto; es para pruebas/entrega académica, no para publicar en Google Play.

## Criterio de cierre

- Pruebas automatizadas locales: **58/58 aprobadas** (52 Flutter + 6 backend).
- Pruebas contra Render/PostgreSQL/Firestore y dispositivo físico: **pendientes**.
- Defectos o evidencia faltante: despliegue, migración, credenciales seguras,
  pruebas reales de permisos, lectura Galaxy Watch y actualización en Android.
- Decisión: **[x] Repetir pruebas** cuando estén disponibles los servicios y dispositivos reales.
- Revisó: asistente de código  Fecha: 23/10/2026
