const assert = require('node:assert/strict');
const { once } = require('node:events');
const { after, before, test } = require('node:test');
const jwt = require('jsonwebtoken');
const {
  createApp,
  measurementQuery,
  validateMeasurement,
  validateReport,
  validateReportId,
} = require('../src/app');
const { hashPassword, verifyPassword } = require('../src/security');

const jwtSecret = 'test-secret-with-at-least-32-bytes-long';
const users = new Map();
let server;
let baseUrl;
let reportStreamFailure;

const pool = {
  async query(sql, values = []) {
    if (sql.includes('INSERT INTO app_users')) {
      const [id, displayName, email, passwordHash] = values;
      if ([...users.values()].some((user) => user.email === email)) {
        const error = new Error('duplicate email');
        error.code = '23505';
        throw error;
      }
      const user = { id, display_name: displayName, email, role: 'patient', password_hash: passwordHash };
      users.set(id, user);
      return { rows: [user], rowCount: 1 };
    }
    if (sql.includes('FROM app_users WHERE email')) {
      const user = [...users.values()].find((item) => item.email === values[0]);
      return { rows: user ? [user] : [], rowCount: user ? 1 : 0 };
    }
    if (sql.includes('FROM app_users u') && sql.includes('WHERE u.id')) {
      const user = users.get(values[0]);
      return {
        rows: user
          ? [{ ...user, assigned_patient_uids: [] }]
          : [],
        rowCount: user ? 1 : 0,
      };
    }
    if (sql === 'SELECT 1') return { rows: [{ '?column?': 1 }], rowCount: 1 };
    throw new Error(`Unexpected SQL in test: ${sql}`);
  },
};

before(async () => {
  const reportCollection = {
    limit: () => ({ get: async () => ({ docs: [] }) }),
    where: () => reportCollection,
    onSnapshot: (onData, onError) => {
      queueMicrotask(() => {
        if (reportStreamFailure) {
          onError(reportStreamFailure);
        } else {
          onData({ docs: [] });
        }
      });
      return () => {};
    },
  };
  const firestore = {
    collection: () => reportCollection,
  };
  const app = createApp({ pool, firestore, jwtSecret });
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (server) {
    server.close();
    await once(server, 'close');
  }
});

test('registration stores a password hash and starts with patient role', async () => {
  const response = await fetch(`${baseUrl}/api/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      displayName: 'Paciente Demo',
      email: 'PACIENTE@example.com',
      password: 'ClaveSegura123',
      role: 'admin',
    }),
  });
  const body = await response.json();
  const stored = users.get(body.user.uid);

  assert.equal(response.status, 201);
  assert.equal(body.user.role, 'patient');
  assert.equal(body.user.email, 'paciente@example.com');
  assert.notEqual(stored.password_hash, 'ClaveSegura123');
  assert.equal(await verifyPassword('ClaveSegura123', stored.password_hash), true);
});

test('registration rejects duplicate email and login rejects a wrong password', async () => {
  const duplicate = await fetch(`${baseUrl}/api/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      displayName: 'Otro Nombre',
      email: 'paciente@example.com',
      password: 'OtraClave123',
    }),
  });
  const duplicateBody = await duplicate.json();
  const wrongPassword = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email: 'paciente@example.com',
      password: 'Incorrecta123',
    }),
  });

  assert.equal(duplicate.status, 409);
  assert.match(duplicateBody.message, /Ya existe/);
  assert.equal(wrongPassword.status, 401);
});

test('login returns the profile and unauthorized requests are rejected', async () => {
  const login = await fetch(`${baseUrl}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email: 'paciente@example.com',
      password: 'ClaveSegura123',
    }),
  });
  const session = await login.json();
  const me = await fetch(`${baseUrl}/api/auth/me`, {
    headers: { authorization: `Bearer ${session.token}` },
  });
  const profile = await me.json();
  const unauthorized = await fetch(`${baseUrl}/api/measurements`);

  assert.equal(login.status, 200);
  assert.equal(me.status, 200);
  assert.equal(profile.user.uid, session.user.uid);
  assert.equal(unauthorized.status, 401);
});

test('report event stream sends the initial authorized snapshot', async () => {
  const uid = 'admin-stream-test-id';
  users.set(uid, {
    id: uid,
    display_name: 'Admin Demo',
    email: 'admin-stream@example.com',
    role: 'admin',
    password_hash: 'unused',
  });
  const token = jwt.sign({ sub: uid }, jwtSecret, { issuer: 'biomedica-api' });
  const response = await fetch(`${baseUrl}/api/reports/stream`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const reader = response.body.getReader();
  const { value } = await reader.read();
  await reader.cancel();

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/event-stream/);
  assert.match(new TextDecoder().decode(value), /"reports":\[\]/);
});

test('report event stream hides internal error details', async () => {
  reportStreamFailure = new Error('clinic_turns_ticket_code_key');
  const uid = 'admin-stream-error-test-id';
  users.set(uid, {
    id: uid,
    display_name: 'Admin Demo',
    email: 'admin-stream-error@example.com',
    role: 'admin',
    password_hash: 'unused',
  });
  const token = jwt.sign({ sub: uid }, jwtSecret, { issuer: 'biomedica-api' });

  try {
    const response = await fetch(`${baseUrl}/api/reports/stream`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const reader = response.body.getReader();
    const { value } = await reader.read();
    await reader.cancel();
    const event = new TextDecoder().decode(value);

    assert.equal(response.status, 200);
    assert.match(event, /No se pudieron actualizar los reportes/);
    assert.doesNotMatch(event, /clinic_turns_ticket_code_key/);
  } finally {
    reportStreamFailure = null;
  }
});

test('server rejects invalid measurements, report fields, and document IDs', () => {
  const now = Date.now();
  const measurement = {
    readingAt: new Date(now).toISOString(),
    source: 'wear_os_sensor',
    deviceName: 'Galaxy Watch',
    heartRateBpm: 72,
    oxygenSaturationPercent: null,
    bodyTemperatureCelsius: null,
  };

  assert.equal(validateMeasurement(measurement, now), null);
  assert.equal(
    validateMeasurement({
      ...measurement,
      readingAt: new Date(now - 6 * 60_000).toISOString(),
    }, now),
    null,
  );
  assert.ok(validateMeasurement({
    ...measurement,
    readingAt: new Date(now - 25 * 60 * 60_000).toISOString(),
  }, now));
  assert.ok(validateMeasurement({
    ...measurement,
    source: 'ble_hr',
    readingAt: new Date(now - 6 * 60_000).toISOString(),
  }, now));
  assert.match(
    validateMeasurement({ ...measurement, heartRateBpm: 221 }, now),
    /frecuencia cardiaca/,
  );
  assert.equal(validateReport({
    equipment: 'Monitor',
    description: 'No enciende',
    priority: 'Media',
  }), null);
  assert.ok(validateReport({ equipment: '', description: 'Falla', priority: 'Media' }));
  assert.throws(() => validateReportId('REP/001'), /ID del reporte/);
});

test('measurement queries scope patient and doctor access in SQL', () => {
  const patientQuery = measurementQuery({ uid: 'patient-id', role: 'patient' });
  const doctorQuery = measurementQuery({ uid: 'doctor-id', role: 'doctor' });
  const adminQuery = measurementQuery({ uid: 'admin-id', role: 'admin' });

  assert.match(patientQuery.sql, /WHERE m\.owner_uid = \$1/);
  assert.deepEqual(patientQuery.values, ['patient-id']);
  assert.match(doctorQuery.sql, /JOIN patient_assignments/);
  assert.deepEqual(doctorQuery.values, ['doctor-id']);
  assert.match(adminQuery.sql, /ORDER BY m\.reading_at DESC/);
});

test('doctor sessions cannot create measurements or manage accounts', async () => {
  const uid = 'doctor-test-id';
  users.set(uid, {
    id: uid,
    display_name: 'Doctor Demo',
    email: 'doctor@example.com',
    role: 'doctor',
    password_hash: 'unused',
  });
  const token = jwt.sign({ sub: uid }, jwtSecret, { issuer: 'biomedica-api' });
  const headers = {
    authorization: `Bearer ${token}`,
    'content-type': 'application/json',
  };

  const measurementResponse = await fetch(`${baseUrl}/api/measurements`, {
    method: 'POST',
    headers,
    body: JSON.stringify({}),
  });
  const adminResponse = await fetch(`${baseUrl}/api/admin/users`, { headers });

  assert.equal(measurementResponse.status, 403);
  assert.equal(adminResponse.status, 403);
});
