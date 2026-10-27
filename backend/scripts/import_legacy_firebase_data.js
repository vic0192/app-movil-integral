const { randomBytes } = require('node:crypto');
const { cert, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { Pool } = require('pg');
const { hashPassword, normalizeEmail, textLength } = require('../src/security');

async function main() {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!process.env.DATABASE_URL || !serviceAccountJson) {
    throw new Error('DATABASE_URL y FIREBASE_SERVICE_ACCOUNT_JSON son requeridos.');
  }
  const firebaseApp = initializeApp({
    credential: cert(JSON.parse(serviceAccountJson)),
  });
  const firestore = getFirestore(firebaseApp);
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });

  const profiles = await firestore.collection('users').get();
  const measurements = await firestore.collection('mediciones').get();
  const importedUsers = new Map();
  const client = await pool.connect();
  let assignmentCount = 0;
  let measurementCount = 0;

  try {
    await client.query('BEGIN');
    for (const document of profiles.docs) {
      const data = document.data();
      const email = normalizeEmail(data.email);
      const name = typeof data.displayName === 'string'
        ? data.displayName.trim()
        : '';
      const role = ['patient', 'doctor', 'admin'].includes(data.role)
        ? data.role
        : 'patient';
      if (
        !email ||
        email.length > 254 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        !name ||
        textLength(name) > 100
      ) {
        throw new Error(`El perfil ${document.id} contiene campos inválidos; no se importaron los datos.`);
      }
      const unusablePassword = randomBytes(32).toString('base64url');
      const passwordHash = await hashPassword(unusablePassword);
      await client.query(
        `INSERT INTO app_users (id, display_name, email, password_hash, role, created_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          document.id,
          name,
          email,
          passwordHash,
          role,
          data.createdAt?.toDate?.() ?? new Date(),
        ],
      );
      const assignments = Array.isArray(data.assignedPatientUids)
        ? [...new Set(data.assignedPatientUids.filter((uid) => typeof uid === 'string'))]
        : [];
      if (role === 'doctor' && assignments.length > 30) {
        throw new Error(`El perfil ${document.id} excede el máximo de 30 pacientes; no se importaron los datos.`);
      }
      importedUsers.set(document.id, {
        role,
        assignments,
      });
    }

    for (const [doctorUid, profile] of importedUsers) {
      if (profile.role !== 'doctor') continue;
      for (const patientUid of new Set(profile.assignments)) {
        if (importedUsers.get(patientUid)?.role !== 'patient') continue;
        const inserted = await client.query(
          `INSERT INTO patient_assignments (doctor_uid, patient_uid)
           VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [doctorUid, patientUid],
        );
        assignmentCount += 1;
      }
    }

    for (const document of measurements.docs) {
      const data = document.data();
      if (!importedUsers.has(data.ownerUid)) continue;
      const readingAt = data.readingAt?.toDate?.();
      if (
        !(readingAt instanceof Date) ||
        !Number.isFinite(readingAt.getTime()) ||
        !['wear_os_sensor', 'ble_hr'].includes(data.source) ||
        !Number.isInteger(data.heartRateBpm) ||
        data.heartRateBpm < 30 ||
        data.heartRateBpm > 220
      ) {
        continue;
      }
      const deviceName = typeof data.deviceName === 'string'
        ? data.deviceName.trim()
        : '';
      if (!deviceName || textLength(deviceName) > 100) continue;
      const oxygen = data.oxygenSaturationPercent;
      const temperature = data.bodyTemperatureCelsius;
      if (oxygen != null && (!Number.isInteger(oxygen) || oxygen < 50 || oxygen > 100)) {
        continue;
      }
      if (temperature != null && (!Number.isFinite(temperature) || temperature < 25 || temperature > 45)) {
        continue;
      }
      const createdAt = data.createdAt?.toDate?.() ?? readingAt;
      await client.query(
        `INSERT INTO measurements (
           legacy_measurement_id, owner_uid, reading_at, created_at, source,
           device_name, heart_rate_bpm, oxygen_saturation_percent,
           body_temperature_celsius
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (legacy_measurement_id) DO NOTHING`,
        [
          document.id,
          data.ownerUid,
          readingAt,
          createdAt,
          data.source,
          deviceName,
          data.heartRateBpm,
          oxygen ?? null,
          temperature ?? null,
        ],
      );
      measurementCount += inserted.rowCount;
    }
    await client.query('COMMIT');
    console.log(
      `Imported ${importedUsers.size} account(s), ${assignmentCount} assignment(s), and ${measurementCount} measurement(s).`,
    );
    console.log('Imported accounts have random, unusable passwords. Set each password using set_user_password.js after verifying the user.');
    console.log('Reports remain in Firestore and retain their original owner IDs.');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error('Legacy data import failed:', error);
  process.exitCode = 1;
});
