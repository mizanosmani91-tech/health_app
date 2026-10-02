import { Express, Request } from 'express';
import { z } from 'zod';
import { Pharmacy, StockItem, StockStatus } from '@prisma/client';
import { Db } from '../prisma';
import { contribute, lookupCatalog } from '../catalog';
import { openStatus } from '../hours';
import { HttpError, day, hhmm, n, optMoney, optText, parse, simpleLimit, text } from '../http';

const pharmacyJson = (p: Pharmacy) => ({
  id: p.id, ownerId: p.ownerId, name: p.name, address: p.address, phone: p.phone, licenseNo: p.licenseNo,
  // isOpen = open right now (switch AND hours AND not the weekly off day); manualOpen = the owner's switch
  status: p.status, isOpen: openStatus(p).open, closedReason: openStatus(p).reason, manualOpen: p.isOpen, openFrom: p.openFrom, openTo: p.openTo, weeklyOff: p.weeklyOff, lat: p.lat, lng: p.lng,
  notifyNew: p.notifyNew, createdAt: p.createdAt,
});

const stockJson = (s: StockItem) => ({
  id: s.id, name: s.name, genericName: s.genericName, form: s.form, qty: n(s.qty), unit: s.unit,
  buyPrice: n(s.buyPrice), sellPrice: n(s.sellPrice), expiry: s.expiry, batchNo: s.batchNo, manufacturer: s.manufacturer, barcode: s.barcode,
  status: s.status, updatedAt: s.updatedAt,
});

const stockBody = z.object({
  name: text(160),
  genericName: optText(160),
  form: optText(40),
  qty: optMoney,
  unit: optText(30),
  buyPrice: optMoney,
  sellPrice: optMoney,
  expiry: day.nullable().optional(),
  batchNo: optText(60),
  manufacturer: optText(120),
  barcode: z.preprocess((v) => (v === '' ? null : v), z.string().regex(/^\d{8,14}$/, 'barcode must be 8-14 digits').nullable().optional()),
  status: z.nativeEnum(StockStatus).default('in'),
});

export function pharmacyRoutes(app: Express, d: { db: Db; authed: any }) {
  const { db } = d;
  const owner = [d.authed];
  const patient = [d.authed];
  const mine = async (req: Request) => {
    const p = await db.pharmacy.findUnique({ where: { ownerId: req.user!.id } });
    if (!p) throw new HttpError(404, 'no pharmacy yet');
    return p;
  };

  app.post('/pharmacy', ...owner, async (req, res) => {
    const b = parse(
      z.object({ name: text(120), address: text(300), phone: text(30), licenseNo: text(60), licenseImage: z.string().min(1).max(1_000_000), lat: z.number().min(-90).max(90).optional(), lng: z.number().min(-180).max(180).optional() }),
      req.body,
    );
    const bytes = Buffer.from(b.licenseImage, 'base64');
    if (bytes.length < 1000 || bytes.length > 700 * 1024) throw new HttpError(400, 'licence photo must be under 700 KB');
    if (await db.pharmacy.findUnique({ where: { ownerId: req.user!.id } })) throw new HttpError(409, 'pharmacy already registered');
    const p = await db.pharmacy.create({
      data: {
        ownerId: req.user!.id, name: b.name, address: b.address, phone: b.phone, licenseNo: b.licenseNo, lat: b.lat, lng: b.lng,
        license: { create: { image: bytes } },
      },
    });
    res.status(201).json(pharmacyJson(p));
  });

  app.get('/pharmacy', ...owner, async (req, res) => res.json(pharmacyJson(await mine(req))));

  // `status` and ownership are deliberately not editable here.
  app.patch('/pharmacy', ...owner, async (req, res) => {
    const p = await mine(req);
    const b = parse(
      z.object({
        name: text(120), address: text(300), phone: text(30), licenseNo: text(60), isOpen: z.boolean(),
        notifyNew: z.boolean(), openFrom: hhmm, openTo: hhmm, weeklyOff: optText(100),
        lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180),
      }).partial(),
      req.body,
    );
    res.json(pharmacyJson(await db.pharmacy.update({ where: { id: p.id }, data: b })));
  });

  // ---- stock (prices etc. are only ever returned to the owner)
  app.get('/stock', ...owner, async (req, res) => {
    const p = await mine(req);
    res.json((await db.stockItem.findMany({ where: { pharmacyId: p.id }, orderBy: { name: 'asc' } })).map(stockJson));
  });
  // A verified pharmacy's scanned products feed the shared catalog (identity only: name/generic/form/maker).
  const share = async (p: Pharmacy, s: StockItem) => {
    if (s.barcode && p.status === 'verified') {
      await contribute(db, p.id, { barcode: s.barcode, name: s.name, genericName: s.genericName, form: s.form, manufacturer: s.manufacturer });
    }
  };

  // What do we know about this barcode from other pharmacies? (404 = nobody has named it yet)
  app.get('/catalog/:code', ...owner, async (req, res) => {
    await mine(req);
    if (!/^\d{8,14}$/.test(req.params.code)) throw new HttpError(400, 'barcode must be 8-14 digits');
    const hit = await lookupCatalog(db, req.params.code);
    if (!hit) throw new HttpError(404, 'not found');
    res.json(hit);
  });

  // Look a scanned pack up in this pharmacy's own product list (404 = first time we see it).
  app.get('/stock/barcode/:code', ...owner, async (req, res) => {
    const p = await mine(req);
    if (!/^\d{8,14}$/.test(req.params.code)) throw new HttpError(400, 'barcode must be 8-14 digits');
    const s = await db.stockItem.findFirst({ where: { pharmacyId: p.id, barcode: req.params.code } });
    if (!s) throw new HttpError(404, 'not found');
    res.json(stockJson(s));
  });
  app.post('/stock', ...owner, async (req, res) => {
    const p = await mine(req);
    const s = await db.stockItem.create({ data: { ...parse(stockBody, req.body), pharmacyId: p.id } });
    await share(p, s);
    res.status(201).json(stockJson(s));
  });
  app.patch('/stock/:id', ...owner, async (req, res) => {
    const p = await mine(req);
    const data = parse(stockBody.partial(), req.body);
    if (!Object.keys(data).length) throw new HttpError(400, 'nothing to update');
    const r = await db.stockItem.updateMany({ where: { id: req.params.id, pharmacyId: p.id }, data });
    if (!r.count) throw new HttpError(404, 'not found');
    const s = (await db.stockItem.findUnique({ where: { id: req.params.id } }))!;
    await share(p, s);
    res.json(stockJson(s));
  });
  app.delete('/stock/:id', ...owner, async (req, res) => {
    const p = await mine(req);
    await db.stockItem.deleteMany({ where: { id: req.params.id, pharmacyId: p.id } });
    res.status(204).end();
  });

  // ---- patient search: only name + in/low/out, only verified shops, never prices/quantities
  app.post('/search', ...patient, simpleLimit(60), async (req, res) => {
    const { names } = parse(z.object({ names: z.array(text(120)).min(1).max(20) }), req.body);
    const phs = await db.pharmacy.findMany({
      where: { status: 'verified' }, orderBy: { name: 'asc' }, take: 100,
      select: { id: true, name: true, address: true, phone: true, isOpen: true, openFrom: true, openTo: true, weeklyOff: true },
    });
    const ids = phs.map((p) => p.id);
    const rank: Record<string, number> = { in: 3, low: 2, out: 1 };
    const best = new Map<string, string>(); // `${pharmacyId}|${name}` -> status
    for (const q of names) {
      const rows = await db.stockItem.findMany({
        where: {
          pharmacyId: { in: ids },
          OR: [{ name: { contains: q, mode: 'insensitive' } }, { genericName: { contains: q, mode: 'insensitive' } }],
        },
        select: { pharmacyId: true, status: true },
      });
      for (const r of rows) {
        const k = `${r.pharmacyId}|${q}`;
        if ((rank[r.status] ?? 0) > (rank[best.get(k) ?? ''] ?? 0)) best.set(k, r.status);
      }
    }
    const upd = await db.stockItem.groupBy({ by: ['pharmacyId'], where: { pharmacyId: { in: ids } }, _max: { updatedAt: true } });
    const updAt = new Map(upd.map((u) => [u.pharmacyId, u._max.updatedAt]));
    res.json(
      phs.flatMap((p) =>
        names.map((q) => ({
          pharmacyId: p.id, pharmacyName: p.name, address: p.address, phone: p.phone, isOpen: openStatus(p).open,
          medicineName: q, status: best.get(`${p.id}|${q}`) ?? 'unknown', updatedAt: updAt.get(p.id) ?? null,
        })),
      ),
    );
  });
}
