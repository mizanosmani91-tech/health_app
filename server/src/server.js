import path from 'node:path';
import fs from 'node:fs';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { createApp } from './app.js';
import { openDb } from './db.js';

const env = (k, d) => process.env[k] ?? d;
const dataDir = env('DATA_DIR', './data');
fs.mkdirSync(dataDir, { recursive: true });

// Google client ids whose ID tokens we accept (the *web* client id; comma-separated for several).
const audiences = env('GOOGLE_CLIENT_IDS', '').split(',').map((s) => s.trim()).filter(Boolean);
if (!audiences.length) throw new Error('GOOGLE_CLIENT_IDS is required');

const jwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
async function verifyGoogle(idToken) {
  const { payload } = await jwtVerify(idToken, jwks, {
    issuer: ['https://accounts.google.com', 'accounts.google.com'], audience: audiences,
  });
  if (!payload.sub) throw new Error('no sub');
  return { sub: payload.sub, email: payload.email, name: payload.name };
}

const app = createApp({
  db: openDb(path.join(dataDir, 'app.db')),
  verifyGoogle,
  jwtSecret: env('JWT_SECRET', ''),
  adminKey: env('ADMIN_KEY', ''),
  dataDir,
});
const port = Number(env('PORT', '8787'));
app.listen(port, '127.0.0.1', () => console.log(`health-diary-server listening on 127.0.0.1:${port}`));
