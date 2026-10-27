const fs = require('node:fs/promises');
const path = require('node:path');
const { cert, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { Pool } = require('pg');
const { createApp } = require('./app');

async function start() {
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret || Buffer.byteLength(jwtSecret) < 32) {
    throw new Error('JWT_SECRET debe tener al menos 32 bytes aleatorios.');
  }
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON es requerido para guardar reportes en Firestore.');
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_PUBLISHABLE_KEY) {
    throw new Error('SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY son requeridos para verificar sesiones de reportes.');
  }

  const serviceAccount = JSON.parse(serviceAccountJson);
  const firebaseApp = initializeApp({ credential: cert(serviceAccount) });
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  const migration = await fs.readFile(
    path.join(__dirname, '..', 'migrations', '001_initial_schema.sql'),
    'utf8',
  );
  await pool.query(migration);

  const app = createApp({
    pool,
    firestore: getFirestore(firebaseApp),
    jwtSecret,
    supabaseUrl: process.env.SUPABASE_URL,
    supabasePublishableKey: process.env.SUPABASE_PUBLISHABLE_KEY,
  });
  const port = Number(process.env.PORT || 3000);
  const server = app.listen(port, '0.0.0.0', () => {
    console.log(`BioMedica API listening on port ${port}`);
  });

  const shutdown = async () => {
    server.close();
    await pool.end();
    await firebaseApp.delete();
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

start().catch((error) => {
  console.error('BioMedica API failed to start:', error);
  process.exitCode = 1;
});
