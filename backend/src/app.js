const express = require('express');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const { randomUUID } = require('node:crypto');
const {
  hashPassword,
  normalizeEmail,
  textLength,
  validateCredentials,
  verifyPassword,
} = require('./security');

const roles = new Set(['patient', 'doctor', 'admin']);
const reportPriorities = new Set(['Baja', 'Media', 'Alta']);
const allowedMeasurementSources = new Set(['wear_os_sensor', 'ble_hr']);

function createApp({
  pool,
  firestore,
  jwtSecret,
  supabaseUrl = process.env.SUPABASE_URL,
  supabasePublishableKey = process.env.SUPABASE_PUBLISHABLE_KEY,
  supabaseFetch = globalThis.fetch,
}) {
  if (!pool || !firestore || !jwtSecret || Buffer.byteLength(jwtSecret) < 32) {
    throw new Error('La API requiere PostgreSQL, Firestore y un JWT_SECRET de al menos 32 bytes.');
  }

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(express.json({ limit: '32kb' }));
  app.use('/api/auth', rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 30,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
  }));

  app.get('/health', async (_request, response, next) => {
    try {
      await pool.query('SELECT 1');
      await firestore.collection('reportes').limit(1).get();
      response.json({ status: 'ok' });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/auth/register', async (request, response, next) => {
    try {
      const { displayName, email, password } = request.body ?? {};
      const validation = validateCredentials({ displayName, email, password }, true);
      if (validation) return response.status(400).json({ message: validation });

      const normalizedName = displayName.trim();
      const normalizedEmail = normalizeEmail(email);
      const passwordHash = await hashPassword(password);
      const result = await pool.query(
        `INSERT INTO app_users (id, display_name, email, password_hash)
         VALUES ($1, $2, $3, $4)
         RETURNING id, display_name, email, role`,
        [randomUUID(), normalizedName, normalizedEmail, passwordHash],
      );
      if (!result.rowCount) {
        return response.status(409).json({ message: 'Ya existe una cuenta con ese correo.' });
      }
      return sendSession(response, result.rows[0], jwtSecret, 201);
    } catch (error) {
      if (error.code === '23505') {
        return response.status(409).json({ message: 'Ya existe una cuenta con ese correo.' });
      }
      return next(error);
    }
  });

  app.post('/api/auth/login', async (request, response, next) => {
    try {
      const { email, password } = request.body ?? {};
      const validation = validateCredentials({ email, password }, false);
      if (validation) return response.status(400).json({ message: validation });

      const result = await pool.query(
        `SELECT id, display_name, email, role, password_hash
         FROM app_users WHERE email = $1 AND password_hash IS NOT NULL`,
        [normalizeEmail(email)],
      );
      const user = result.rows[0];
      if (!user || !(await verifyPassword(password, user.password_hash))) {
        return response.status(401).json({ message: 'Correo o contraseña incorrectos.' });
      }
      return sendSession(response, user, jwtSecret, 200);
    } catch (error) {
      return next(error);
    }
  });

  app.use('/api', authenticate({
    pool,
    jwtSecret,
    supabaseUrl,
    supabasePublishableKey,
    supabaseFetch,
  }));

  app.get('/api/auth/me', (request, response) => {
    response.json({ user: request.user });
  });

  app.get('/api/admin/users', requireRole('admin'), async (_request, response, next) => {
    try {
      const result = await pool.query(
        `SELECT u.id, u.display_name, u.email, u.role,
                COALESCE(
                  json_agg(a.patient_uid) FILTER (WHERE a.patient_uid IS NOT NULL),
                  '[]'
                ) AS assigned_patient_uids
         FROM app_users u
         LEFT JOIN patient_assignments a ON a.doctor_uid = u.id
         GROUP BY u.id
         ORDER BY u.display_name`,
      );
      response.json({ users: result.rows.map(publicUser) });
    } catch (error) {
      next(error);
    }
  });

  app.patch('/api/admin/users/:uid/role', requireRole('admin'), async (request, response, next) => {
    const { uid } = request.params;
    const { role } = request.body ?? {};
    if (!roles.has(role)) {
      return response.status(400).json({ message: 'El rol seleccionado no es válido.' });
    }
    if (uid === request.user.uid) {
      return response.status(400).json({ message: 'No puedes cambiar tu propio rol de administrador.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const updated = await client.query(
        `UPDATE app_users SET role = $1 WHERE id = $2
         RETURNING id, display_name, email, role`,
        [role, uid],
      );
      if (!updated.rowCount) {
        await client.query('ROLLBACK');
        return response.status(404).json({ message: 'No existe la cuenta indicada.' });
      }
      if (role !== 'doctor') {
        await client.query('DELETE FROM patient_assignments WHERE doctor_uid = $1', [uid]);
      }
      await client.query('COMMIT');
      response.json({ user: publicUser(updated.rows[0]) });
    } catch (error) {
      await client.query('ROLLBACK');
      next(error);
    } finally {
      client.release();
    }
  });

  app.put('/api/admin/users/:doctorUid/assignments', requireRole('admin'), async (request, response, next) => {
    const { doctorUid } = request.params;
    const patientUids = request.body?.patientUids;
    if (!Array.isArray(patientUids) || patientUids.some((uid) => typeof uid !== 'string')) {
      return response.status(400).json({ message: 'La lista de pacientes no es válida.' });
    }
    const uniquePatientUids = [...new Set(patientUids)];
    if (uniquePatientUids.length > 30) {
      return response.status(400).json({ message: 'Un médico puede tener como máximo 30 pacientes asignados.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const doctor = await client.query(
        `SELECT id FROM app_users WHERE id = $1 AND role = 'doctor' FOR UPDATE`,
        [doctorUid],
      );
      if (!doctor.rowCount) {
        await client.query('ROLLBACK');
        return response.status(400).json({ message: 'Solo se pueden asignar pacientes a una cuenta de médico.' });
      }
      if (uniquePatientUids.length) {
        const patients = await client.query(
          `SELECT id FROM app_users WHERE role = 'patient' AND id = ANY($1::text[])`,
          [uniquePatientUids],
        );
        if (patients.rowCount !== uniquePatientUids.length) {
          await client.query('ROLLBACK');
          return response.status(400).json({ message: 'Todas las cuentas asignadas deben ser pacientes habilitados.' });
        }
      }
      await client.query('DELETE FROM patient_assignments WHERE doctor_uid = $1', [doctorUid]);
      for (const patientUid of uniquePatientUids) {
        await client.query(
          'INSERT INTO patient_assignments (doctor_uid, patient_uid) VALUES ($1, $2)',
          [doctorUid, patientUid],
        );
      }
      await client.query('COMMIT');
      response.json({ doctorUid, patientUids: uniquePatientUids });
    } catch (error) {
      await client.query('ROLLBACK');
      next(error);
    } finally {
      client.release();
    }
  });

  app.get('/api/measurements', async (request, response, next) => {
    try {
      const { sql, values } = measurementQuery(request.user);
      const result = await pool.query(sql, values);
      response.json({ measurements: result.rows.map(publicMeasurement) });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/measurements', requireRole('patient'), async (request, response, next) => {
    const validation = validateMeasurement(request.body ?? {});
    if (validation) return response.status(400).json({ message: validation });
    try {
      const input = request.body;
      const result = await pool.query(
        `INSERT INTO measurements (
           owner_uid, reading_at, source, device_name, heart_rate_bpm,
           oxygen_saturation_percent, body_temperature_celsius
         ) VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          request.user.uid,
          input.readingAt,
          input.source,
          input.deviceName.trim(),
          input.heartRateBpm,
          input.oxygenSaturationPercent ?? null,
          input.bodyTemperatureCelsius ?? null,
        ],
      );
      response.status(201).json({ measurement: publicMeasurement(result.rows[0]) });
    } catch (error) {
      next(error);
    }
  });

  app.get('/api/reports', async (request, response, next) => {
    try {
      const collection = firestore.collection('reportes');
      let query = collection;
      if (request.user.role === 'patient') {
        query = collection.where('ownerUid', '==', request.user.uid);
      } else if (request.user.role === 'doctor') {
        const patientUids = request.user.authProvider === 'supabase'
          ? request.user.assignedPatientUids
          : (await pool.query(
            'SELECT patient_uid FROM patient_assignments WHERE doctor_uid = $1',
            [request.user.uid],
          )).rows.map((row) => row.patient_uid);
        if (patientUids.length === 0) return response.json({ reports: [] });
        query = collection.where('ownerUid', 'in', patientUids);
      }
      const snapshot = await query.get();
      const reports = snapshot.docs
        .map((document) => publicReport(document.id, document.data()))
        .filter(Boolean)
        .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));
      response.json({ reports });
    } catch (error) {
      next(error);
    }
  });

  app.post('/api/reports', requireRole('patient'), async (request, response, next) => {
    const validation = validateReport(request.body ?? {});
    if (validation) return response.status(400).json({ message: validation });
    try {
      const { id, ...fields } = request.body;
      const collection = firestore.collection('reportes');
      const document = id ? collection.doc(validateReportId(id)) : collection.doc();
      const now = new Date();
      const malestar = (fields.malestar ?? fields.equipment).trim();
      const report = {
        equipment: malestar,
        malestar,
        otherMalestar: fields.otherMalestar?.trim() || null,
        description: fields.description.trim(),
        priority: fields.priority,
        ownerUid: request.user.uid,
        onsetAt: fields.onsetAt ? new Date(fields.onsetAt) : now,
        createdAt: now,
        updatedAt: now,
      };
      await document.create(report);
      response.status(201).json({ report: publicReport(document.id, report) });
    } catch (error) {
      if (error.code === 6 || error.code === 'already-exists') {
        return response.status(409).json({ message: `Ya existe el reporte "${request.body.id}".` });
      }
      if (error instanceof InputError) {
        return response.status(400).json({ message: error.message });
      }
      return next(error);
    }
  });

  app.put('/api/reports/:id', async (request, response, next) => {
    if (request.user.role === 'doctor') {
      return response.status(403).json({ message: 'Los médicos pueden consultar reportes, pero no modificarlos.' });
    }
    const validation = validateReport(request.body ?? {});
    if (validation) return response.status(400).json({ message: validation });
    try {
      const document = firestore.collection('reportes').doc(validateReportId(request.params.id));
      const snapshot = await document.get();
      if (!snapshot.exists) return response.status(404).json({ message: `No existe el reporte "${request.params.id}".` });
      if (request.user.role !== 'admin' && snapshot.data().ownerUid !== request.user.uid) {
        return response.status(403).json({ message: 'No tienes permiso para modificar este reporte.' });
      }
      const malestar = (request.body.malestar ?? request.body.equipment).trim();
      await document.update({
        equipment: malestar,
        malestar,
        otherMalestar: request.body.otherMalestar?.trim() || null,
        description: request.body.description.trim(),
        priority: request.body.priority,
        onsetAt: request.body.onsetAt
          ? new Date(request.body.onsetAt)
          : snapshot.data().onsetAt ?? snapshot.data().createdAt,
        updatedAt: new Date(),
      });
      const updated = await document.get();
      response.json({ report: publicReport(document.id, updated.data()) });
    } catch (error) {
      if (error instanceof InputError) return response.status(400).json({ message: error.message });
      next(error);
    }
  });

  app.delete('/api/reports/:id', async (request, response, next) => {
    if (request.user.role === 'doctor') {
      return response.status(403).json({ message: 'Los médicos pueden consultar reportes, pero no eliminarlos.' });
    }
    try {
      const document = firestore.collection('reportes').doc(validateReportId(request.params.id));
      const snapshot = await document.get();
      if (!snapshot.exists) return response.status(404).json({ message: `No existe el reporte "${request.params.id}".` });
      if (request.user.role !== 'admin' && snapshot.data().ownerUid !== request.user.uid) {
        return response.status(403).json({ message: 'No tienes permiso para eliminar este reporte.' });
      }
      await document.delete();
      response.status(204).end();
    } catch (error) {
      if (error instanceof InputError) return response.status(400).json({ message: error.message });
      next(error);
    }
  });

  app.use((error, _request, response, _next) => {
    console.error('API request failed:', error);
    if (response.headersSent) return;
    response.status(500).json({ message: 'La API no pudo completar la operación.' });
  });

  return app;
}

function sendSession(response, user, jwtSecret, statusCode) {
  const token = jwt.sign({ sub: user.id }, jwtSecret, { expiresIn: '7d', issuer: 'biomedica-api' });
  response.status(statusCode).json({
    token,
    user: publicUser(user),
  });
}

function authenticate({
  pool,
  jwtSecret,
  supabaseUrl,
  supabasePublishableKey,
  supabaseFetch,
}) {
  return async (request, response, next) => {
    const authorization = request.get('authorization') ?? '';
    const match = /^Bearer (.+)$/.exec(authorization);
    if (!match) return response.status(401).json({ message: 'Inicia sesión para continuar.' });
    try {
      const claims = jwt.verify(match[1], jwtSecret, { issuer: 'biomedica-api' });
      const result = await pool.query(
        `SELECT u.id, u.display_name, u.email, u.role,
                COALESCE(
                  json_agg(a.patient_uid) FILTER (WHERE a.patient_uid IS NOT NULL),
                  '[]'
                ) AS assigned_patient_uids
         FROM app_users u
         LEFT JOIN patient_assignments a ON a.doctor_uid = u.id
         WHERE u.id = $1
         GROUP BY u.id`,
        [claims.sub],
      );
      if (!result.rowCount) {
        if (isReportRequest(request.path) && supabaseUrl && supabasePublishableKey) {
          return authenticateSupabase({
            token: match[1],
            request,
            response,
            next,
            supabaseUrl,
            supabasePublishableKey,
            supabaseFetch,
          });
        }
        return response.status(401).json({ message: 'La sesión ya no está habilitada.' });
      }
      request.user = publicUser(result.rows[0]);
      next();
    } catch (error) {
      if (error.name === 'JsonWebTokenError' || error.name === 'TokenExpiredError') {
        if (isReportRequest(request.path) && supabaseUrl && supabasePublishableKey) {
          return authenticateSupabase({
            token: match[1],
            request,
            response,
            next,
            supabaseUrl,
            supabasePublishableKey,
            supabaseFetch,
          });
        }
        if (isReportRequest(request.path) && (!supabaseUrl || !supabasePublishableKey)) {
          return response.status(503).json({
            message: 'La API de reportes no tiene configurada la autenticación Supabase.',
          });
        }
        return response.status(401).json({ message: 'La sesión venció. Inicia sesión nuevamente.' });
      }
      next(error);
    }
  };
}

function isReportRequest(path) {
  return path === '/reports' || path.startsWith('/reports/');
}

async function authenticateSupabase({
  token,
  request,
  response,
  next,
  supabaseUrl,
  supabasePublishableKey,
  supabaseFetch,
}) {
  try {
    const baseUrl = supabaseUrl.replace(/\/+$/, '');
    const headers = {
      apikey: supabasePublishableKey,
      authorization: `Bearer ${token}`,
    };
    const authResponse = await supabaseFetch(`${baseUrl}/auth/v1/user`, { headers });
    if (authResponse.status === 401 || authResponse.status === 403) {
      return response.status(401).json({ message: 'La sesión de Supabase venció. Inicia sesión nuevamente.' });
    }
    if (!authResponse.ok) {
      return response.status(503).json({ message: 'No se pudo verificar la sesión con Supabase.' });
    }
    const authUser = await authResponse.json();
    if (typeof authUser.id !== 'string' || !authUser.id) {
      return response.status(401).json({ message: 'Supabase no devolvió una identidad válida.' });
    }

    const profileQuery = new URLSearchParams({
      select: 'id,role,first_name,last_name,email',
      id: `eq.${authUser.id}`,
    });
    const profileResponse = await supabaseFetch(
      `${baseUrl}/rest/v1/profiles?${profileQuery}`,
      { headers },
    );
    if (!profileResponse.ok) {
      return response.status(503).json({ message: 'No se pudo consultar el perfil de Supabase.' });
    }
    const profiles = await profileResponse.json();
    const profile = Array.isArray(profiles) ? profiles[0] : null;
    if (!profile || profile.id !== authUser.id || !roles.has(profile.role)) {
      return response.status(403).json({ message: 'La cuenta no tiene un perfil habilitado para reportes.' });
    }

    let assignedPatientUids = [];
    if (profile.role === 'doctor') {
      const assignmentQuery = new URLSearchParams({
        select: 'patient_uid',
        doctor_uid: `eq.${authUser.id}`,
      });
      const assignmentsResponse = await supabaseFetch(
        `${baseUrl}/rest/v1/doctor_patient_assignments?${assignmentQuery}`,
        { headers },
      );
      if (!assignmentsResponse.ok) {
        return response.status(503).json({ message: 'No se pudieron consultar las asignaciones clínicas.' });
      }
      const assignments = await assignmentsResponse.json();
      if (!Array.isArray(assignments)) {
        return response.status(503).json({ message: 'Supabase devolvió asignaciones inválidas.' });
      }
      assignedPatientUids = assignments.map((assignment) => assignment.patient_uid);
    }

    request.user = {
      uid: authUser.id,
      displayName: [profile.first_name, profile.last_name].filter(Boolean).join(' '),
      email: profile.email ?? authUser.email,
      role: profile.role,
      assignedPatientUids,
      authProvider: 'supabase',
    };
    return next();
  } catch (error) {
    console.error('Supabase report authentication failed:', error);
    return response.status(503).json({ message: 'No se pudo verificar la sesión con Supabase.' });
  }
}

function requireRole(...allowed) {
  return (request, response, next) => {
    if (!allowed.includes(request.user.role)) {
      return response.status(403).json({ message: 'Tu rol no tiene permiso para realizar esta operación.' });
    }
    next();
  };
}

function publicUser(row) {
  return {
    uid: row.id,
    displayName: row.display_name ?? row.displayName,
    email: row.email,
    role: row.role,
    assignedPatientUids: row.assigned_patient_uids ?? row.assignedPatientUids ?? [],
  };
}

function publicMeasurement(row) {
  return {
    id: row.id,
    ownerUid: row.owner_uid,
    readingAt: new Date(row.reading_at).toISOString(),
    createdAt: new Date(row.created_at).toISOString(),
    source: row.source,
    deviceName: row.device_name,
    heartRateBpm: row.heart_rate_bpm,
    oxygenSaturationPercent: row.oxygen_saturation_percent,
    bodyTemperatureCelsius: row.body_temperature_celsius == null
      ? null
      : Number(row.body_temperature_celsius),
  };
}

function measurementQuery(user) {
  if (user.role === 'admin') {
    return {
      sql: `SELECT m.* FROM measurements m ORDER BY m.reading_at DESC LIMIT 500`,
      values: [],
    };
  }
  if (user.role === 'doctor') {
    return {
      sql: `SELECT m.* FROM measurements m
            JOIN patient_assignments a ON a.patient_uid = m.owner_uid
            WHERE a.doctor_uid = $1 ORDER BY m.reading_at DESC LIMIT 500`,
      values: [user.uid],
    };
  }
  return {
    sql: `SELECT m.* FROM measurements m
          WHERE m.owner_uid = $1 ORDER BY m.reading_at DESC LIMIT 500`,
    values: [user.uid],
  };
}

function validateMeasurement(input, now = Date.now()) {
  const readingAt = Date.parse(input.readingAt);
  if (!Number.isFinite(readingAt) || readingAt > now + 2 * 60_000 || now - readingAt > 5 * 60_000) {
    return 'La lectura está vencida o tiene una fecha no válida.';
  }
  if (!allowedMeasurementSources.has(input.source)) return 'La fuente de la lectura no es compatible.';
  if (typeof input.deviceName !== 'string' || !input.deviceName.trim() || textLength(input.deviceName.trim()) > 100) {
    return 'El nombre del dispositivo no es válido.';
  }
  if (!Number.isInteger(input.heartRateBpm) || input.heartRateBpm < 30 || input.heartRateBpm > 220) {
    return 'La frecuencia cardiaca está fuera del rango permitido.';
  }
  const oxygen = input.oxygenSaturationPercent;
  if (oxygen != null && (!Number.isInteger(oxygen) || oxygen < 50 || oxygen > 100)) {
    return 'El valor de SpO₂ está fuera del rango permitido.';
  }
  const temperature = input.bodyTemperatureCelsius;
  if (temperature != null && (!Number.isFinite(temperature) || temperature < 25 || temperature > 45)) {
    return 'La temperatura está fuera del rango permitido.';
  }
  return null;
}

function validateReport(input) {
  const malestar = input.malestar ?? input.equipment;
  if (typeof malestar !== 'string' || !malestar.trim() || textLength(malestar.trim()) > 100) {
    return 'Selecciona o escribe el malestar (máximo 100 caracteres).';
  }
  if (malestar.trim().toLowerCase() === 'otro' &&
      (typeof input.otherMalestar !== 'string' ||
       !input.otherMalestar.trim() ||
       textLength(input.otherMalestar.trim()) > 100)) {
    return 'Describe el otro malestar (máximo 100 caracteres).';
  }
  if (typeof input.description !== 'string' || !input.description.trim() || textLength(input.description.trim()) > 500) {
    return 'La descripción debe tener entre 1 y 500 caracteres.';
  }
  if (!reportPriorities.has(input.priority)) return 'Selecciona una prioridad válida.';
  if (input.onsetAt != null) {
    const onsetAt = Date.parse(input.onsetAt);
    if (!Number.isFinite(onsetAt) || onsetAt > Date.now()) {
      return 'La fecha de inicio del malestar no es válida.';
    }
  }
  return null;
}

function validateReportId(value) {
  if (typeof value !== 'string') throw new InputError('El ID del reporte no es válido.');
  const id = value.trim();
  if (!id || id.includes('/') || textLength(id) > 100) {
    throw new InputError('El ID del reporte no es válido.');
  }
  return id;
}

function publicReport(id, data) {
  if (!data || (!('equipment' in data) && !('malestar' in data)) ||
      !('description' in data) || !('priority' in data)) {
    return null;
  }
  return {
    id,
    equipment: data.equipment ?? data.malestar,
    malestar: data.malestar ?? data.equipment,
    otherMalestar: data.otherMalestar ?? null,
    description: data.description,
    priority: data.priority,
    onsetAt: toNullableIsoDate(data.onsetAt),
    createdAt: toIsoDate(data.createdAt),
    updatedAt: toIsoDate(data.updatedAt),
  };
}

function toNullableIsoDate(value) {
  if (value == null) return null;
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function toIsoDate(value) {
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
}

class InputError extends Error {}

module.exports = {
  createApp,
  measurementQuery,
  publicMeasurement,
  publicReport,
  publicUser,
  validateMeasurement,
  validateReport,
  validateReportId,
};
