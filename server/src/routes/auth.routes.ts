import { Express } from 'express';
import { z } from 'zod';
import { Role } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, parse, simpleLimit } from '../http';

export function authRoutes(
  app: Express,
  d: { db: Db; verifyGoogle: (t: string) => Promise<{ sub: string; email?: string; name?: string }>; issue: (id: string) => Promise<string>; authed: any },
) {
  const json = (u: { id: string; email: string | null; name: string | null; role: Role | null }) => ({
    id: u.id, email: u.email, name: u.name, role: u.role,
  });

  app.post('/auth/google', simpleLimit(20), async (req, res) => {
    const { idToken } = parse(z.object({ idToken: z.string().min(10).max(4096) }), req.body);
    let g;
    try {
      g = await d.verifyGoogle(idToken);
    } catch {
      throw new HttpError(401, 'invalid Google token');
    }
    const u = await d.db.user.upsert({
      where: { googleSub: g.sub },
      update: {},
      create: { googleSub: g.sub, email: g.email ?? null, name: g.name ?? g.email ?? null },
    });
    res.json({ token: await d.issue(u.id), user: json(u) });
  });

  app.get('/me', d.authed, (req, res) => res.json(json(req.user!)));

  // Write-once: a role can be chosen exactly one time.
  app.post('/me/role', d.authed, async (req, res) => {
    const { role } = parse(z.object({ role: z.nativeEnum(Role) }), req.body);
    const r = await d.db.user.updateMany({ where: { id: req.user!.id, role: null }, data: { role } });
    if (!r.count) throw new HttpError(409, 'role already chosen');
    res.json(json({ ...req.user!, role }));
  });
}
