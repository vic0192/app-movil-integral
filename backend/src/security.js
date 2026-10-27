const { randomBytes, scrypt: scryptCallback, timingSafeEqual } = require('node:crypto');
const { promisify } = require('node:util');

const scrypt = promisify(scryptCallback);

async function hashPassword(password) {
  const salt = randomBytes(16);
  const hash = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

async function verifyPassword(password, storedHash) {
  const [algorithm, saltHex, hashHex] = storedHash.split('$');
  if (algorithm !== 'scrypt' || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = await scrypt(password, Buffer.from(saltHex, 'hex'), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function textLength(value) {
  return [...value].length;
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

function validateCredentials({ displayName, email, password }, registering) {
  const normalizedEmail = normalizeEmail(email);
  if (
    normalizedEmail.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)
  ) {
    return 'Ingresa un correo electrónico válido.';
  }
  if (typeof password !== 'string' || textLength(password) < 8 || textLength(password) > 30) {
    return 'La contraseña debe tener entre 8 y 30 caracteres.';
  }
  if (
    registering &&
    (typeof displayName !== 'string' ||
      textLength(displayName.trim()) < 2 ||
      textLength(displayName.trim()) > 100)
  ) {
    return 'El nombre debe tener entre 2 y 100 caracteres.';
  }
  return null;
}

module.exports = {
  hashPassword,
  normalizeEmail,
  textLength,
  validateCredentials,
  verifyPassword,
};
