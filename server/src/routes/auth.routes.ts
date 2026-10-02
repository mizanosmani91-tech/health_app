import { Express } from 'express';
import { z } from 'zod';
import { Role } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, parse, simpleLimit } from '../http';

export function authRoutes(
  app: Express,
  d: { db: Db; verifyGoogle: (t: string) => Promise<{ sub: string; email?: string; name?: string }>; issue: (id: string) => Promise<string>; authed: any },
) {
  const json = (u: { id: string; email: string | null; name: string | null; role: Role | null; phone?: string | null; birthYear?: number | null; bloodGroup?: string | null }) => ({
    id: u.id, email: u.email, name: u.name, role: u.role,
    phone: u.phone ?? null, birthYear: u.birthYear ?? null, bloodGroup: u.bloodGroup ?? null,
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

  // The role is only the mode the app opens in (a preference). It is NOT an authorization boundary:
  // one account may be a patient and own a pharmacy; access is decided by ownership.
  app.post('/me/role', d.authed, async (req, res) => {
    const { role } = parse(z.object({ role: z.nativeEnum(Role) }), req.body);
    await d.db.user.update({ where: { id: req.user!.id }, data: { role } });
    res.json(json({ ...req.user!, role }));
  });

  // Basic account details only (name, mobile, birth year, blood group). Medicines, visits, tests and
  // prescriptions never come here; they stay on the person's phone / own Drive.
  app.put('/me/profile', d.authed, async (req, res) => {
    const b = parse(
      z.object({
        name: z.string().trim().min(1).max(80),
        phone: z.string().trim().regex(/^\+?[0-9]{10,15}$/, 'invalid phone number'),
        birthYear: z.preprocess((v) => (v === '' ? null : v), z.coerce.number().int().min(1900).max(new Date().getFullYear()).nullable().optional()),
        bloodGroup: z.enum(['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-', '']).optional(),
      }),
      req.body,
    );
    const u = await d.db.user.update({
      where: { id: req.user!.id },
      data: { name: b.name, phone: b.phone, birthYear: b.birthYear ?? null, bloodGroup: b.bloodGroup || null },
    });
    res.json(json(u));
  });
}
