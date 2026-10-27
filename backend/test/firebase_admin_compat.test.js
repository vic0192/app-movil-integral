const assert = require('node:assert/strict');
const { test } = require('node:test');
const { cert, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

test('Firebase Admin v14 exposes modular app and Firestore initialization APIs', () => {
  assert.equal(typeof cert, 'function');
  assert.equal(typeof initializeApp, 'function');
  assert.equal(typeof getFirestore, 'function');
});
