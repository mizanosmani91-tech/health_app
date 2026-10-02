/* Imports a CSV of medicine names into the Drug table (idempotent).
 *   npx tsx scripts/import-drugs.ts data/generics.csv
 * Columns (header required): name,generic,strength,form,manufacturer,kind   (kind = brand | generic)
 * Use only data you are allowed to use (e.g. a public register whose terms permit it). No prices are stored. */
import 'dotenv/config';
import fs from 'node:fs';
import { PrismaClient } from '@prisma/client';

function parseCsv(text: string): string[][] {
  const rows: string[][] = []; let row: string[] = [], cur = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cur); cur = ''; if (row.some((x) => x.trim())) rows.push(row); row = []; }
    else cur += c;
  }
  if (cur || row.length) { row.push(cur); if (row.some((x) => x.trim())) rows.push(row); }
  return rows;
}

(async () => {
  const file = process.argv[2];
  if (!file) throw new Error('usage: import-drugs.ts <file.csv>');
  const [head, ...rows] = parseCsv(fs.readFileSync(file, 'utf8'));
  const idx = (n: string) => head.map((h) => h.trim().toLowerCase()).indexOf(n);
  const col = { name: idx('name'), generic: idx('generic'), strength: idx('strength'), form: idx('form'), manufacturer: idx('manufacturer'), kind: idx('kind') };
  if (col.name < 0) throw new Error('CSV needs a "name" column');
  const prisma = new PrismaClient();
  const get = (r: string[], i: number) => (i >= 0 ? (r[i] ?? '').trim() : '');
  let n = 0;
  for (const r of rows) {
    const name = get(r, col.name);
    if (!name) continue;
    const data = { name, generic: get(r, col.generic), strength: get(r, col.strength), form: get(r, col.form), manufacturer: get(r, col.manufacturer), kind: get(r, col.kind) || 'brand' };
    await prisma.drug.upsert({
      where: { name_form_strength_manufacturer: { name: data.name, form: data.form, strength: data.strength, manufacturer: data.manufacturer } },
      update: { generic: data.generic, kind: data.kind }, create: data,
    });
    n++;
  }
  console.log(`imported/updated ${n} rows`);
  await prisma.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
