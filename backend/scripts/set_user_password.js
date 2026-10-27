const readline = require('node:readline');
const { Pool } = require('pg');
const { hashPassword, normalizeEmail, textLength } = require('../src/security');

function readHidden(prompt) {
  return new Promise((resolve, reject) => {
    if (!process.stdin.isTTY || !process.stdin.setRawMode) {
      reject(new Error('Ejecuta este comando en una terminal interactiva.'));
      return;
    }
    readline.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdout.write(prompt);
    let value = '';
    const onKey = (character, key) => {
      if (key.ctrl && key.name === 'c') {
        cleanup();
        reject(new Error('Operación cancelada.'));
      } else if (key.name === 'return') {
        cleanup();
        process.stdout.write('\n');
        resolve(value);
      } else if (key.name === 'backspace') {
        value = [...value].slice(0, -1).join('');
      } else if (!key.ctrl && !key.meta) {
        value += character;
      }
    };
    const cleanup = () => {
      process.stdin.off('keypress', onKey);
      process.stdin.setRawMode(false);
    };
    process.stdin.on('keypress', onKey);
  });
}

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL es requerido.');
  }
  const email = normalizeEmail(process.argv[2] ?? '');
  if (!email || email.length > 254) {
    throw new Error('Uso: node scripts/set_user_password.js <correo>');
  }
  const password = await readHidden('Nueva contraseña (8–30 caracteres): ');
  if (textLength(password) < 8 || textLength(password) > 30) {
    throw new Error('La contraseña debe tener entre 8 y 30 caracteres.');
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  try {
    const result = await pool.query(
      'UPDATE app_users SET password_hash = $1 WHERE email = $2 RETURNING id',
      [await hashPassword(password), email],
    );
    if (!result.rowCount) throw new Error('No existe una cuenta con ese correo.');
    console.log('Contraseña actualizada.');
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error('Password update failed:', error.message);
  process.exitCode = 1;
});
