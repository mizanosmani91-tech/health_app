import { Express, NextFunction, Request, Response } from 'express';
import { z } from 'zod';
import { PharmacyStatus } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, parse, safeEqual, simpleLimit } from '../http';

/** Manual pharmacy verification. Only mounted when ADMIN_KEY is configured. */
export function adminRoutes(app: Express, d: { db: Db; adminKey: string }) {
  const guard = (req: Request, _res: Response, next: NextFunction) =>
    next(safeEqual(req.get('x-admin-key') ?? '', d.adminKey) ? undefined : new HttpError(401, 'admin key required'));
  const lim = simpleLimit(30);

  app.get('/admin/pharmacies', lim, guard, async (req, res) => {
    const { status } = parse(z.object({ status: z.nativeEnum(PharmacyStatus).optional() }), req.query);
    const rows = await d.db.pharmacy.findMany({ where: status ? { status } : {}, orderBy: { createdAt: 'asc' }, include: { owner: { select: { email: true } } } });
    res.json(rows.map(({ owner, ...p }) => ({ ...p, ownerEmail: owner.email })));
  });

  app.get('/admin/pharmacies/:id/license', lim, guard, async (req, res) => {
    const l = await d.db.licensePhoto.findUnique({ where: { pharmacyId: req.params.id } });
    if (!l) throw new HttpError(404, 'no licence photo');
    res.type('image/jpeg').send(Buffer.from(l.image));
  });

  app.post('/admin/pharmacies/:id/status', lim, guard, async (req, res) => {
    const { status } = parse(z.object({ status: z.nativeEnum(PharmacyStatus) }), req.body);
    const r = await d.db.pharmacy.updateMany({ where: { id: req.params.id }, data: { status } });
    if (!r.count) throw new HttpError(404, 'not found');
    res.json({ ok: true });
  });
}
