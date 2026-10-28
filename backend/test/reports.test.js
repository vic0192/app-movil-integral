const assert = require('node:assert/strict');
const { once } = require('node:events');
const { after, before, test } = require('node:test');
const jwt = require('jsonwebtoken');
const { createApp, validateReport, validateReportId } = require('../src/app');

const jwtSecret = 'test-secret-with-at-least-32-bytes-long';
const users = new Map();
const reports = new Map();
const supabaseUsers = new Map();
const supabaseTokens = new Map();
const doctorAssignments = new Map();
let server;
let baseUrl;

const pool = {
  async query(sql, values = []) {
    if (sql.includes('INSERT INTO app_users')) {
      const [id, displayName, email, passwordHash] = values;
      if ([...users.values()].some((user) => user.email === email)) {
        const error = new Error('duplicate email');
        error.code = '23505';
        throw error;
      }
      const user = {
        id,
        display_name: displayName,
        email,
        role: 'patient',
        password_hash: passwordHash,
      };
      users.set(id, user);
      return { rows: [user], rowCount: 1 };
    }
    if (sql.includes('FROM app_users WHERE email')) {
      const user = [...users.values()].find((item) => item.email === values[0]);
      return { rows: user ? [user] : [], rowCount: user ? 1 : 0 };
    }
    if (sql.includes('FROM app_users u') && sql.includes('WHERE u.id')) {
      const user = users.get(values[0]);
      return { rows: user ? [{ ...user, assigned_patient_uids: [] }] : [], rowCount: user ? 1 : 0 };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  },
};

const firestore = {
  collection(name) {
    assert.equal(name, 'reportes');
    return {
      where(field, operator, value) {
        assert.equal(field, 'ownerUid');
        return {
          async get() {
            const matches = operator === '=='
              ? (ownerUid) => ownerUid === value
              : (ownerUid) => value.includes(ownerUid);
            return snapshot([...reports.entries()].filter(([, data]) => matches(data.ownerUid)));
          },
        };
      },
      async get() {
        return snapshot([...reports.entries()]);
      },
      doc(id) {
        return {
          id,
          async create(data) {
            if (reports.has(id)) {
              const error = new Error('already exists');
              error.code = 6;
              throw error;
            }
            reports.set(id, { ...data });
          },
          async get() {
            const data = reports.get(id);
            return { exists: data !== undefined, data: () => data };
          },
          async update(fields) {
            const data = reports.get(id);
            if (!data) throw new Error('report not found');
            reports.set(id, { ...data, ...fields });
          },
          async delete() {
            reports.delete(id);
          },
        };
      },
    };
  },
};

function snapshot(entries) {
  return {
    docs: entries.map(([id, data]) => ({ id, data: () => data })),
  };
}

async function supabaseFetch(url, options) {
  const parsedUrl = new URL(url);
  const token = options.headers.authorization?.replace(/^Bearer /, '');
  const user = supabaseTokens.get(token);
  if (parsedUrl.pathname === '/auth/v1/user') {
    return Response.json(user ?? {}, { status: user ? 200 : 401 });
  }
  if (!user) return Response.json({}, { status: 401 });
  if (parsedUrl.pathname === '/rest/v1/profiles') {
    const profile = supabaseUsers.get(parsedUrl.searchParams.get('id')?.slice(3));
    return Response.json(profile ? [profile] : []);
  }
  if (parsedUrl.pathname === '/rest/v1/doctor_patient_assignments') {
    const uid = parsedUrl.searchParams.get('doctor_uid')?.slice(3);
    return Response.json((doctorAssignments.get(uid) ?? []).map((patient_uid) => ({ patient_uid })));
  }
  return Response.json({}, { status: 404 });
}

before(async () => {
  const app = createApp({
    pool,
    firestore,
    jwtSecret,
    supabaseUrl: 'https://supabase.example.test',
    supabasePublishableKey: 'test-publishable-key',
    supabaseFetch,
  });
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test('serves the confirmation handoff page without caching or leaking the code', async () => {
  const response = await fetch(
    `${baseUrl}/auth/confirmed?code=one-time-code&state=signup`,
  );
  const page = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/html/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  assert.match(page, /Correo confirmado/);
  assert.match(page, /window\.location\.search \+ window\.location\.hash/);
  assert.doesNotMatch(page, /one-time-code/);
});

after(async () => {
  if (server) {
    server.close();
    await once(server, 'close');
  }
  users.clear();
  reports.clear();
});

async function registerPatient(email) {
  const response = await fetch(`${baseUrl}/api/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      displayName: 'Paciente de prueba',
      email,
      password: 'ClaveSegura123',
    }),
  });
  assert.equal(response.status, 201);
  return response.json();
}

function authHeaders(token) {
  return {
    authorization: `Bearer ${token}`,
    'content-type': 'application/json',
  };
}

function supabaseHeaders(token) {
  return {
    authorization: `Bearer ${token}`,
    'content-type': 'application/json',
  };
}

function registerSupabaseUser(uid, role, token) {
  const user = { id: uid, email: `${uid}@example.test` };
  supabaseTokens.set(token, user);
  supabaseUsers.set(uid, {
    id: uid,
    role,
    first_name: 'Usuario',
    last_name: 'Prueba',
    email: user.email,
  });
  return user;
}

test('report validation accepts a valid draft', () => {
  assert.equal(
    validateReport({
      equipment: 'Monitor de prueba',
      description: 'Falla sintética',
      priority: 'Media',
    }),
    null,
  );
  assert.equal(
    validateReport({
      malestar: 'Otro',
      otherMalestar: 'Visión borrosa temporal',
      description: 'Comenzó esta mañana',
      priority: 'Media',
      onsetAt: new Date().toISOString(),
    }),
    null,
  );
});

test('report validation accepts maximum text and ID lengths', () => {
  assert.equal(
    validateReport({
      equipment: 'E'.repeat(100),
      description: 'D'.repeat(500),
      priority: 'Alta',
    }),
    null,
  );
  assert.equal(validateReportId('R'.repeat(100)), 'R'.repeat(100));
});

test('report validation rejects invalid fields and IDs', () => {
  assert.match(
    validateReport({
      equipment: '   ',
      description: 'Falla sintética',
      priority: 'Media',
    }),
    /malestar/,
  );
  assert.match(
    validateReport({
      malestar: 'Otro',
      description: 'Descripción',
      priority: 'Media',
    }),
    /otro malestar/,
  );
  assert.throws(() => validateReportId('REP/001'), /ID del reporte/);
});

test('patient completes report create, read, update, and delete over HTTP', async () => {
  const session = await registerPatient('report-flow@example.com');
  const headers = authHeaders(session.token);
  const draft = {
    id: 'REP-TEST-001',
    equipment: 'Monitor de prueba',
    description: 'No enciende',
    priority: 'Media',
  };

  const created = await fetch(`${baseUrl}/api/reports`, {
    method: 'POST',
    headers,
    body: JSON.stringify(draft),
  });
  const createdBody = await created.json();
  assert.equal(created.status, 201);
  assert.equal(createdBody.report.id, draft.id);
  assert.equal(reports.get(draft.id).ownerUid, session.user.uid);

  const listed = await fetch(`${baseUrl}/api/reports`, { headers });
  const listedBody = await listed.json();
  assert.equal(listed.status, 200);
  assert.equal(listedBody.reports.length, 1);
  assert.equal(listedBody.reports[0].equipment, draft.equipment);

  const updated = await fetch(`${baseUrl}/api/reports/${draft.id}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify({ ...draft, description: 'Revisión completada' }),
  });
  const updatedBody = await updated.json();
  assert.equal(updated.status, 200);
  assert.equal(updatedBody.report.description, 'Revisión completada');
  assert.equal(reports.get(draft.id).description, 'Revisión completada');

  const deleted = await fetch(`${baseUrl}/api/reports/${draft.id}`, {
    method: 'DELETE',
    headers,
  });
  const afterDelete = await fetch(`${baseUrl}/api/reports`, { headers });
  assert.equal(deleted.status, 204);
  assert.equal((await afterDelete.json()).reports.length, 0);
  assert.equal(reports.has(draft.id), false);
});

test('report API rejects invalid and unauthenticated operations without writes', async () => {
  const session = await registerPatient('report-errors@example.com');
  const invalid = await fetch(`${baseUrl}/api/reports`, {
    method: 'POST',
    headers: authHeaders(session.token),
    body: JSON.stringify({
      id: 'REP-TEST-INVALID',
      equipment: '   ',
      description: 'Falla de prueba',
      priority: 'Media',
    }),
  });
  const unauthorized = await fetch(`${baseUrl}/api/reports`);

  assert.equal(invalid.status, 400);
  assert.equal(unauthorized.status, 401);
  assert.equal(reports.has('REP-TEST-INVALID'), false);
});

test('Supabase patient sessions isolate Firestore reports by owner', async () => {
  registerSupabaseUser('supabase-patient-a', 'patient', 'patient-token-a');
  registerSupabaseUser('supabase-patient-b', 'patient', 'patient-token-b');
  const headers = supabaseHeaders('patient-token-a');
  const onsetAt = new Date(Date.now() - 60_000).toISOString();
  const created = await fetch(`${baseUrl}/api/reports`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      id: 'REP-SUPABASE-001',
      malestar: 'Otro',
      otherMalestar: 'Visión borrosa temporal',
      description: 'Reporte de integración',
      priority: 'Media',
      onsetAt,
    }),
  });
  const createdBody = await created.json();
  assert.equal(created.status, 201);
  assert.equal(reports.get('REP-SUPABASE-001').ownerUid, 'supabase-patient-a');
  assert.equal(reports.get('REP-SUPABASE-001').malestar, 'Otro');
  assert.equal(reports.get('REP-SUPABASE-001').otherMalestar, 'Visión borrosa temporal');
  assert.equal(createdBody.report.malestar, 'Otro');
  assert.equal(new Date(createdBody.report.onsetAt).toISOString(), onsetAt);

  const ownReports = await fetch(`${baseUrl}/api/reports`, { headers });
  const otherReports = await fetch(`${baseUrl}/api/reports`, {
    headers: supabaseHeaders('patient-token-b'),
  });
  const unauthorizedUpdate = await fetch(`${baseUrl}/api/reports/REP-SUPABASE-001`, {
    method: 'PUT',
    headers: supabaseHeaders('patient-token-b'),
    body: JSON.stringify({
      equipment: 'Equipo alterado',
      description: 'Intento no autorizado',
      priority: 'Alta',
    }),
  });
  assert.deepEqual((await ownReports.json()).reports.map((report) => report.id), [
    'REP-SUPABASE-001',
  ]);
  assert.deepEqual((await otherReports.json()).reports, []);
  assert.equal(unauthorizedUpdate.status, 403);
  assert.equal(reports.get('REP-SUPABASE-001').description, 'Reporte de integración');
});

test('Supabase doctors can read assigned patients only and cannot create reports', async () => {
  registerSupabaseUser('supabase-patient-assigned', 'patient', 'assigned-patient-token');
  registerSupabaseUser('supabase-patient-unassigned', 'patient', 'unassigned-patient-token');
  registerSupabaseUser('supabase-doctor', 'doctor', 'doctor-token');
  doctorAssignments.set('supabase-doctor', ['supabase-patient-assigned']);
  reports.set('REP-ASSIGNED', {
    ownerUid: 'supabase-patient-assigned',
    equipment: 'Equipo A',
    description: 'Reporte asignado',
    priority: 'Media',
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  reports.set('REP-UNASSIGNED', {
    ownerUid: 'supabase-patient-unassigned',
    equipment: 'Equipo B',
    description: 'Reporte no asignado',
    priority: 'Media',
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  const listed = await fetch(`${baseUrl}/api/reports`, {
    headers: supabaseHeaders('doctor-token'),
  });
  const create = await fetch(`${baseUrl}/api/reports`, {
    method: 'POST',
    headers: supabaseHeaders('doctor-token'),
    body: JSON.stringify({
      id: 'REP-DOCTOR-001',
      equipment: 'Equipo',
      description: 'No permitido',
      priority: 'Media',
    }),
  });

  assert.deepEqual((await listed.json()).reports.map((report) => report.id), [
    'REP-ASSIGNED',
  ]);
  assert.equal(create.status, 403);
  assert.equal(reports.has('REP-DOCTOR-001'), false);
});

test('Supabase report API rejects invalid bearer tokens', async () => {
  const response = await fetch(`${baseUrl}/api/reports`, {
    headers: supabaseHeaders('invalid-token'),
  });

  assert.equal(response.status, 401);
});

test('Supabase reports fall back when a JWT is valid but absent from legacy accounts', async () => {
  const user = registerSupabaseUser(
    'supabase-valid-legacy-miss',
    'patient',
    'placeholder-supabase-token',
  );
  const token = jwt.sign(
    { sub: user.id },
    jwtSecret,
    { issuer: 'biomedica-api', expiresIn: '1h' },
  );
  supabaseTokens.delete('placeholder-supabase-token');
  supabaseTokens.set(token, user);
  const response = await fetch(`${baseUrl}/api/reports`, {
    headers: supabaseHeaders(token),
  });

  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).reports, []);
});
