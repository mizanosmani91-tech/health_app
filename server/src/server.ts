import 'dotenv/config';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { createApp } from './app';
import { prisma } from './prisma';
import { anthropicReader } from './prescription';

const audiences = (process.env.GOOGLE_CLIENT_IDS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
if (!audiences.length) throw new Error('GOOGLE_CLIENT_IDS is required');

const jwks = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
async function verifyGoogle(idToken: string) {
  const { payload } = await jwtVerify(idToken, jwks, {
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
    audience: audiences,
  });
  if (!payload.sub) throw new Error('no sub');
  return { sub: payload.sub, email: payload.email as string | undefined, name: payload.name as string | undefined };
}

const app = createApp({
  db: prisma, verifyGoogle, jwtSecret: process.env.JWT_SECRET ?? '', adminKey: process.env.ADMIN_KEY, log: true,
  readPrescription: process.env.ANTHROPIC_API_KEY ? anthropicReader(process.env.ANTHROPIC_API_KEY) : undefined,
  scanDailyLimit: Number(process.env.SCAN_DAILY_LIMIT ?? 10),
});
const port = Number(process.env.PORT ?? 8787);
app.listen(port, '127.0.0.1', () => console.log(`health-diary-server listening on 127.0.0.1:${port}`));
