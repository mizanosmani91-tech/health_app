import { Express, NextFunction, Request, Response } from 'express';
import { z } from 'zod';
import { PharmacyStatus } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, optText, parse, safeEqual, simpleLimit, text } from '../http';
import { lookupCatalog } from '../catalog';

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

  // Catalog moderation: see what pharmacies wrote for a barcode, and pin a corrected name.
  const code = z.string().regex(/^\d{8,14}$/);
  app.get('/admin/catalog/:code', lim, guard, async (req, res) => {
    const barcode = parse(code, req.params.code);
    const entries = await d.db.catalogEntry.findMany({ where: { barcode }, orderBy: { updatedAt: 'desc' } });
    res.json({ consensus: await lookupCatalog(d.db, barcode), entries: entries.map((e) => ({ pharmacyId: e.pharmacyId, name: e.name, genericName: e.genericName, form: e.form, manufacturer: e.manufacturer })) });
  });
  app.put('/admin/catalog/:code', lim, guard, async (req, res) => {
    const barcode = parse(code, req.params.code);
    const b = parse(z.object({ name: text(160), genericName: optText(160), form: optText(40), manufacturer: optText(120) }), req.body);
    const data = { name: b.name, genericName: b.genericName ?? null, form: b.form ?? null, manufacturer: b.manufacturer ?? null };
    await d.db.catalogOverride.upsert({ where: { barcode }, update: data, create: { barcode, ...data } });
    res.json({ ok: true });
  });
  app.delete('/admin/catalog/:code', lim, guard, async (req, res) => {
    await d.db.catalogOverride.deleteMany({ where: { barcode: parse(code, req.params.code) } });
    res.status(204).end();
  });
}
