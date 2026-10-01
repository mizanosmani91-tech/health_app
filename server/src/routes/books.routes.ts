import { Express, Request } from 'express';
import { z } from 'zod';
import { KhataDirection, KhataEntry, LedgerEntry, LedgerKind, Prisma } from '@prisma/client';
import { Db } from '../prisma';
import { HttpError, day, money, n, optText, parse, text, today } from '../http';

const ledgerJson = (l: LedgerEntry) => ({ id: l.id, kind: l.kind, title: l.title, amount: n(l.amount), entryDate: l.entryDate, createdAt: l.createdAt });
const khataJson = (k: KhataEntry) => ({
  id: k.id, direction: k.direction, partyName: k.partyName, phone: k.phone, amount: n(k.amount), paid: n(k.paid), createdAt: k.createdAt,
});

export function bookRoutes(app: Express, d: { db: Db; authed: any; role: any }) {
  const { db } = d;
  const owner = [d.authed, d.role('owner')];
  const mine = async (req: Request) => {
    const p = await db.pharmacy.findUnique({ where: { ownerId: req.user!.id } });
    if (!p) throw new HttpError(404, 'no pharmacy yet');
    return p;
  };

  app.get('/ledger', ...owner, async (req, res) => {
    const p = await mine(req);
    const { from } = parse(z.object({ from: day.default('0000-01-01') }), req.query);
    const rows = await db.ledgerEntry.findMany({
      where: { pharmacyId: p.id, entryDate: { gte: from } },
      orderBy: [{ entryDate: 'desc' }, { createdAt: 'desc' }], take: 1000,
    });
    res.json(rows.map(ledgerJson));
  });
  app.post('/ledger', ...owner, async (req, res) => {
    const p = await mine(req);
    const b = parse(z.object({ kind: z.nativeEnum(LedgerKind), title: text(160), amount: money, entryDate: day.default(today()) }), req.body);
    res.status(201).json(ledgerJson(await db.ledgerEntry.create({ data: { ...b, pharmacyId: p.id } })));
  });
  app.delete('/ledger/:id', ...owner, async (req, res) => {
    const p = await mine(req);
    await db.ledgerEntry.deleteMany({ where: { id: req.params.id, pharmacyId: p.id } });
    res.status(204).end();
  });

  app.get('/khata', ...owner, async (req, res) => {
    const p = await mine(req);
    const { direction } = parse(z.object({ direction: z.nativeEnum(KhataDirection).default('receivable') }), req.query);
    res.json((await db.khataEntry.findMany({ where: { pharmacyId: p.id, direction }, orderBy: { createdAt: 'asc' } })).map(khataJson));
  });
  app.post('/khata', ...owner, async (req, res) => {
    const p = await mine(req);
    const b = parse(
      z.object({ direction: z.nativeEnum(KhataDirection), partyName: text(120), phone: optText(30), amount: money.refine((v) => v > 0, 'must be positive') }),
      req.body,
    );
    res.status(201).json(khataJson(await db.khataEntry.create({ data: { ...b, pharmacyId: p.id } })));
  });

  // A payment also books income/expense — in one transaction, and the guard `paid + amt <= amount`
  // is evaluated by the database so two simultaneous payments can't overpay.
  app.post('/khata/:id/pay', ...owner, async (req, res) => {
    const p = await mine(req);
    const { amount } = parse(z.object({ amount: money.refine((v) => v > 0, 'must be positive') }), req.body);
    const out = await db.$transaction(async (tx) => {
      const rows = await tx.$queryRaw<{ id: string }[]>(Prisma.sql`
        UPDATE "KhataEntry" SET paid = paid + ${amount}
        WHERE id = ${req.params.id} AND "pharmacyId" = ${p.id} AND paid + ${amount} <= amount
        RETURNING id`);
      if (!rows.length) {
        const k = await tx.khataEntry.findFirst({ where: { id: req.params.id, pharmacyId: p.id } });
        if (!k) throw new HttpError(404, 'not found');
        throw new HttpError(400, `amount must be between 0 and ${Number(k.amount) - Number(k.paid)}`);
      }
      const k = (await tx.khataEntry.findUnique({ where: { id: req.params.id } }))!;
      const rec = k.direction === 'receivable';
      await tx.ledgerEntry.create({
        data: {
          pharmacyId: p.id, kind: rec ? 'income' : 'expense', amount,
          title: `${rec ? 'বাকি আদায়' : 'পরিশোধ'}: ${k.partyName}`, entryDate: today(),
        },
      });
      return k;
    });
    res.json(khataJson(out));
  });
}
