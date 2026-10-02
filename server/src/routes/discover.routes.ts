import { Express } from 'express';
import { z } from 'zod';
import { Db } from '../prisma';
import { parse, simpleLimit } from '../http';
import { FetchPlaces, distanceKm } from '../geo';
import { openStatus } from '../hours';

export function discoverRoutes(app: Express, d: { db: Db; authed: any; places?: FetchPlaces }) {
  const { db } = d;

  // Pharmacies near a point. `registered` = verified shops on this app (can show stock, accept requests);
  // `map` = other pharmacies from OpenStreetMap (name/phone/location only). The caller's position is not stored.
  app.get('/pharmacies/nearby', d.authed, simpleLimit(40), async (req, res) => {
    const q = parse(
      z.object({ lat: z.coerce.number().min(-90).max(90), lng: z.coerce.number().min(-180).max(180), km: z.coerce.number().min(0.5).max(15).default(5) }),
      req.query,
    );
    const within = <T extends { lat: number | null; lng: number | null }>(rows: T[]) =>
      rows
        .filter((r) => r.lat != null && r.lng != null)
        .map((r) => ({ ...r, distanceKm: Math.round(distanceKm(q.lat, q.lng, r.lat!, r.lng!) * 10) / 10 }))
        .filter((r) => r.distanceKm <= q.km)
        .sort((a, b) => a.distanceKm - b.distanceKm);

    const shops = await db.pharmacy.findMany({ where: { status: 'verified', lat: { not: null }, lng: { not: null } }, take: 500 });
    const registered = within(shops).slice(0, 30).map((p) => ({
      id: p.id, name: p.name, address: p.address, phone: p.phone, lat: p.lat, lng: p.lng,
      isOpen: openStatus(p).open, distanceKm: p.distanceKm,
    }));

    let map: ReturnType<typeof within<{ name: string; lat: number; lng: number; phone: string | null; address: string | null }>> = [];
    if (d.places) {
      try {
        const found = await d.places(q.lat, q.lng, Math.round(q.km * 1000));
        // hide map entries that are the same place as a registered shop (within 60 m)
        map = within(found).filter((m) => !registered.some((r) => distanceKm(m.lat, m.lng, r.lat!, r.lng!) < 0.06)).slice(0, 40);
      } catch (e) {
        console.error('map lookup failed:', (e as Error).message);
      }
    }
    res.json({ registered, map });
  });

  // Name suggestions while adding a medicine (own list or stock): brand or generic, any language of the stored text.
  app.get('/drugs/search', d.authed, simpleLimit(120), async (req, res) => {
    const { q } = parse(z.object({ q: z.string().trim().min(2).max(60) }), req.query);
    const rows = await db.drug.findMany({
      where: { OR: [{ name: { contains: q, mode: 'insensitive' } }, { generic: { contains: q, mode: 'insensitive' } }] },
      orderBy: [{ kind: 'asc' }, { name: 'asc' }], take: 15,
    });
    res.json(rows.map((r) => ({ name: r.name, generic: r.generic, strength: r.strength, form: r.form, manufacturer: r.manufacturer })));
  });
}
