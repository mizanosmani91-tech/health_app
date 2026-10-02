import { Db } from './prisma';

export interface CatalogHit {
  barcode: string;
  name: string;
  genericName: string | null;
  form: string | null;
  manufacturer: string | null;
  confirmations: number; // distinct pharmacies that wrote this same name (0 for an admin override)
  source: 'admin' | 'pharmacies';
}

const norm = (s: string) => s.trim().replace(/\s+/g, ' ').toLowerCase();

/** Best known identity for a barcode: admin override, else the name most distinct pharmacies agree on. */
export async function lookupCatalog(db: Db, barcode: string): Promise<CatalogHit | null> {
  const o = await db.catalogOverride.findUnique({ where: { barcode } });
  if (o) {
    return { barcode, name: o.name, genericName: o.genericName, form: o.form, manufacturer: o.manufacturer, confirmations: 0, source: 'admin' };
  }
  const rows = await db.catalogEntry.findMany({ where: { barcode } });
  if (!rows.length) return null;
  const groups = new Map<string, typeof rows>();
  for (const r of rows) {
    const k = norm(r.name);
    groups.set(k, [...(groups.get(k) ?? []), r]);
  }
  const best = [...groups.values()].sort(
    (a, b) => b.length - a.length || +Math.max(...b.map((x) => +x.updatedAt)) - +Math.max(...a.map((x) => +x.updatedAt)),
  )[0];
  // take the most recent writer's details within the winning name group
  const latest = [...best].sort((a, b) => +b.updatedAt - +a.updatedAt)[0];
  const pick = (f: 'genericName' | 'form' | 'manufacturer') => best.map((r) => r[f]).find((v) => !!v) ?? null;
  return {
    barcode, name: latest.name, genericName: latest.genericName ?? pick('genericName'),
    form: latest.form ?? pick('form'), manufacturer: latest.manufacturer ?? pick('manufacturer'),
    confirmations: best.length, source: 'pharmacies',
  };
}

/** Called when a verified pharmacy saves a stock item that has a barcode. */
export async function contribute(
  db: Db, pharmacyId: string,
  e: { barcode: string; name: string; genericName?: string | null; form?: string | null; manufacturer?: string | null },
) {
  const data = { name: e.name, genericName: e.genericName ?? null, form: e.form ?? null, manufacturer: e.manufacturer ?? null };
  await db.catalogEntry.upsert({
    where: { barcode_pharmacyId: { barcode: e.barcode, pharmacyId } },
    update: data,
    create: { barcode: e.barcode, pharmacyId, ...data },
  });
}
