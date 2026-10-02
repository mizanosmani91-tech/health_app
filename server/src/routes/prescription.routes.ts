import { Express } from 'express';
import { z } from 'zod';
import { Db } from '../prisma';
import { HttpError, parse, simpleLimit, today } from '../http';
import { MEDIA_TYPES, ReadPrescription, sanitize } from '../prescription';

export function prescriptionRoutes(
  app: Express,
  d: { db: Db; authed: any; read?: ReadPrescription; dailyLimit: number },
) {
  const { db } = d;

  // Reads a prescription photo into a DRAFT. Nothing is stored (neither the image nor the result);
  // the app shows the draft and the person confirms before anything is saved on their phone.
  app.post('/prescriptions/parse', d.authed, simpleLimit(30), async (req, res) => {
    if (!d.read) throw new HttpError(503, 'prescription reading is not enabled');
    const b = parse(
      z.object({
        consent: z.literal(true),
        mediaType: z.enum(MEDIA_TYPES),
        image: z.string().min(100).max(1_400_000).regex(/^[A-Za-z0-9+/=\s]+$/, 'must be base64'),
      }),
      req.body,
    );
    const day = today();
    // Count first (atomic), so parallel requests cannot slip past the daily cap.
    const u = await db.scanUsage.upsert({
      where: { userId_day: { userId: req.user!.id, day } },
      create: { userId: req.user!.id, day, count: 1 },
      update: { count: { increment: 1 } },
    });
    if (u.count > d.dailyLimit) throw new HttpError(429, 'daily prescription-scan limit reached');

    let draft;
    try {
      draft = await d.read({ mediaType: b.mediaType, base64: b.image.replace(/\s/g, '') });
    } catch (e) {
      // give the attempt back: the person got nothing for it
      await db.scanUsage.update({ where: { userId_day: { userId: req.user!.id, day } }, data: { count: { decrement: 1 } } });
      console.error('prescription read failed:', (e as Error).message);
      throw new HttpError(502, 'could not read the prescription, try a clearer photo');
    }
    res.json({ draft: sanitize(draft), remainingToday: Math.max(0, d.dailyLimit - u.count) });
  });
}
