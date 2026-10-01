import 'express-async-errors';
import express, { NextFunction, Request, Response } from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { Prisma } from '@prisma/client';
import { SignJWT } from 'jose';
import { Db } from './prisma';
import { HttpError, simpleLimit } from './http';
import { makeAuth } from './middleware/auth';
import { authRoutes } from './routes/auth.routes';
import { pharmacyRoutes } from './routes/pharmacy.routes';
import { requestRoutes } from './routes/requests.routes';
import { bookRoutes } from './routes/books.routes';
import { adminRoutes } from './routes/admin.routes';

export interface AppDeps {
  db: Db;
  verifyGoogle: (idToken: string) => Promise<{ sub: string; email?: string; name?: string }>;
  jwtSecret: string;
  adminKey?: string;
  log?: boolean;
}

export function createApp({ db, verifyGoogle, jwtSecret, adminKey, log }: AppDeps) {
  if (!jwtSecret || jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');
  if (adminKey && adminKey.length < 16) throw new Error('ADMIN_KEY must be at least 16 characters');
  const key = new TextEncoder().encode(jwtSecret);
  const issue = (id: string) =>
    new SignJWT({}).setProtectedHeader({ alg: 'HS256' }).setSubject(id).setIssuedAt().setExpirationTime('60d').sign(key);
  const { authed, role } = makeAuth(db, key);

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // behind Caddy
  app.use(helmet());
  if (log) app.use(morgan('tiny'));
  app.use(express.json({ limit: '1.5mb' }));
  app.use(simpleLimit(600));

  app.get('/health', (_req, res) => res.json({ ok: true }));

  authRoutes(app, { db, verifyGoogle, issue, authed });
  pharmacyRoutes(app, { db, authed, role });
  requestRoutes(app, { db, authed, role });
  bookRoutes(app, { db, authed, role });
  if (adminKey) adminRoutes(app, { db, adminKey });

  app.use((_req, _res, next) => next(new HttpError(404, 'not found')));
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'request too large' });
    if (err instanceof SyntaxError) return res.status(400).json({ error: 'invalid JSON' });
    if (err instanceof Prisma.PrismaClientKnownRequestError && ['P2002', 'P2003', 'P2004'].includes(err.code)) {
      return res.status(409).json({ error: 'conflict' });
    }
    console.error(err);
    res.status(500).json({ error: 'server error' });
  });
  return app;
}
