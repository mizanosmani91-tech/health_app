import { Express, Request } from 'express';
import { z } from 'zod';
import { Availability, MedRequest, RequestItem } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, optText, parse, simpleLimit, text } from '../http';

type Full = MedRequest & { items: RequestItem[]; pharmacy?: { name: string; phone: string; ownerId?: string } };
const json = (r: Full, withShop = false) => ({
  id: r.id, pharmacyId: r.pharmacyId, patientId: r.patientId, patientName: r.patientName, status: r.status,
  replyMessage: r.replyMessage, repliedAt: r.repliedAt, createdAt: r.createdAt,
  items: [...r.items].sort((a, b) => a.idx - b.idx).map((i) => ({ name: i.name, days: i.days, availability: i.availability })),
  ...(withShop && r.pharmacy ? { pharmacyName: r.pharmacy.name, pharmacyPhone: r.pharmacy.phone } : {}),
});

export function requestRoutes(app: Express, d: { db: Db; authed: any }) {
  const { db } = d;
  const owner = [d.authed];
  const patient = [d.authed];

  app.post('/requests', ...patient, simpleLimit(60), async (req, res) => {
    const b = parse(
      z.object({
        pharmacyId: z.string().uuid(), patientName: text(80),
        items: z.array(z.object({ name: text(120), days: z.coerce.number().int().min(0).max(365).default(0) })).min(1).max(30),
      }),
      req.body,
    );
    const ph = await db.pharmacy.findFirst({ where: { id: b.pharmacyId, status: 'verified' } });
    if (!ph) throw new HttpError(404, 'pharmacy not available');
    const r = await db.medRequest.create({
      data: {
        pharmacyId: ph.id, patientId: req.user!.id, patientName: b.patientName,
        items: { create: b.items.map((i, idx) => ({ idx, name: i.name, days: i.days })) },
      },
    });
    res.status(201).json({ id: r.id });
  });

  // ?as=owner -> requests sent to my pharmacy; default -> requests I sent as a patient.
  app.get('/requests', d.authed, async (req, res) => {
    const { as } = parse(z.object({ as: z.enum(['owner', 'patient']).default('patient') }), req.query);
    if (as === 'owner') {
      const p = await db.pharmacy.findUnique({ where: { ownerId: req.user!.id } });
      if (!p) throw new HttpError(404, 'no pharmacy yet');
      const rows = await db.medRequest.findMany({ where: { pharmacyId: p.id }, include: { items: true }, orderBy: { createdAt: 'desc' }, take: 300 });
      return res.json(rows.map((r) => json(r)));
    }
    const rows = await db.medRequest.findMany({
      where: { patientId: req.user!.id }, include: { items: true, pharmacy: { select: { name: true, phone: true } } },
      orderBy: { createdAt: 'desc' }, take: 100,
    });
    res.json(rows.map((r) => json(r, true)));
  });

  // 404 (not 403) for other people's requests, so ids can't be probed.
  const load = async (req: Request): Promise<Full> => {
    const r = await db.medRequest.findUnique({ where: { id: req.params.id }, include: { items: true, pharmacy: { select: { name: true, phone: true, ownerId: true } } } });
    const ok = r && (r.patientId === req.user!.id || r.pharmacy.ownerId === req.user!.id);
    if (!r || !ok) throw new HttpError(404, 'not found');
    return r;
  };
  app.get('/requests/:id', d.authed, async (req, res) => res.json(json(await load(req))));

  app.post('/requests/:id/reply', ...owner, async (req, res) => {
    const r = await load(req);
    // Only the shop's owner may answer; the patient who sent the request can read it but not answer it.
    if (r.pharmacy!.ownerId !== req.user!.id) throw new HttpError(404, 'not found');
    const b = parse(z.object({ items: z.array(z.nativeEnum(Availability)), message: optText(500) }), req.body);
    if (b.items.length !== r.items.length) throw new HttpError(400, 'one availability per item required');
    await db.$transaction([
      ...b.items.map((a, idx) => db.requestItem.update({ where: { requestId_idx: { requestId: r.id, idx } }, data: { availability: a } })),
      db.medRequest.update({ where: { id: r.id }, data: { status: 'replied', replyMessage: b.message ?? null, repliedAt: new Date() } }),
    ]);
    res.json(json((await db.medRequest.findUnique({ where: { id: r.id }, include: { items: true } }))!));
  });
}
