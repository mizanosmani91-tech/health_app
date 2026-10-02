import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { PrismaClient } from '@prisma/client';
import { createApp } from '../src/app';

const prisma = new PrismaClient();
let server: Server;
let base: string;
const ADMIN = 'admin-key-1234567890';

// "Google" for tests: the token string carries the identity.
const verifyGoogle = async (t: string) => {
  if (!t.startsWith('good:')) throw new Error('bad');
  const [, sub, name] = t.split(':');
  return { sub, email: `${sub}@x.com`, name };
};

before(async () => {
  const app = createApp({ db: prisma, verifyGoogle, jwtSecret: 'x'.repeat(40), adminKey: ADMIN });
  await new Promise<void>((r) => { server = app.listen(0, '127.0.0.1', r); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  server.close();
  await prisma.$disconnect();
});

async function call(method: string, url: string, o: { token?: string; body?: unknown; admin?: string } = {}) {
  const res = await fetch(base + url, {
    method,
    headers: { 'content-type': 'application/json', ...(o.token ? { authorization: `Bearer ${o.token}` } : {}), ...(o.admin ? { 'x-admin-key': o.admin } : {}) },
    body: o.body ? JSON.stringify(o.body) : undefined,
  });
  const t = await res.text();
  let json: any;
  try { json = JSON.parse(t); } catch { json = t; }
  return { status: res.status, json };
}
async function login(sub: string, role?: string) {
  const r = await call('POST', '/auth/google', { body: { idToken: `good:${sub}:${sub}` } });
  assert.equal(r.status, 200);
  if (role) assert.equal((await call('POST', '/me/role', { token: r.json.token, body: { role } })).status, 200);
  return r.json.token as string;
}
const photo = Buffer.alloc(5000, 7).toString('base64');
const shop = (n: string) => ({ name: n, address: 'a', phone: '1', licenseNo: 'L', licenseImage: photo });

test('rejects bad Google token and unauthenticated calls', async () => {
  assert.equal((await call('POST', '/auth/google', { body: { idToken: 'evil-token-123' } })).status, 401);
  assert.equal((await call('GET', '/me')).status, 401);
  assert.equal((await call('GET', '/me', { token: 'abc.def.ghi' })).status, 401);
});

test('role is a switchable mode, access is decided by ownership', async () => {
  const t = await login('u1', 'patient');
  // a patient has no pharmacy, so owner-only data simply does not exist for them
  assert.equal((await call('GET', '/stock', { token: t })).status, 404);
  assert.equal((await call('GET', '/requests?as=owner', { token: t })).status, 404);
  // switching the mode is allowed any time and is just a preference
  const sw = await call('POST', '/me/role', { token: t, body: { role: 'owner' } });
  assert.equal(sw.status, 200);
  assert.equal((await call('GET', '/me', { token: t })).json.role, 'owner');
  assert.equal((await call('POST', '/me/role', { token: t, body: { role: 'bogus' } })).status, 400);
});

test('one account can be both pharmacy owner and patient', async () => {
  const both = await login('both1', 'owner');
  const other = await login('own8', 'owner');
  const shopB = await call('POST', '/pharmacy', { token: other, body: shop('Other shop') });
  await call('POST', `/admin/pharmacies/${shopB.json.id}/status`, { admin: ADMIN, body: { status: 'verified' } });
  await call('POST', '/stock', { token: other, body: { name: 'Napa', status: 'in' } });
  await call('POST', '/pharmacy', { token: both, body: shop('My shop') });
  // as a patient (same account) search other shops and send a request
  await call('POST', '/me/role', { token: both, body: { role: 'patient' } });
  const found = await call('POST', '/search', { token: both, body: { names: ['Napa'] } });
  assert.equal(found.status, 200);
  assert.equal(found.json[0].status, 'in');
  const rq = await call('POST', '/requests', { token: both, body: { pharmacyId: shopB.json.id, patientName: 'Me', items: [{ name: 'Napa' }] } });
  assert.equal(rq.status, 201);
  // the two views stay separate: my sent requests vs requests to my shop
  assert.equal((await call('GET', '/requests', { token: both })).json.length, 1);
  assert.equal((await call('GET', '/requests?as=owner', { token: both })).json.length, 0);
  // the other shop sees it, and I (not its owner) cannot answer it
  assert.equal((await call('GET', '/requests?as=owner', { token: other })).json.length, 1);
  assert.equal((await call('POST', `/requests/${rq.json.id}/reply`, { token: both, body: { items: ['yes'] } })).status, 404);
  // my own shop's stock is untouched by the patient search results
  assert.equal((await call('GET', '/stock', { token: both })).json.length, 0);
});

test('full pharmacy flow: register, verify, stock, search privacy, request, reply', async () => {
  const owner = await login('owner1', 'owner');
  const patient = await login('pat1', 'patient');
  const reg = await call('POST', '/pharmacy', { token: owner, body: { ...shop('রহমান ফার্মেসি'), address: 'মিরপুর' } });
  assert.equal(reg.status, 201);
  assert.equal(reg.json.status, 'pending');
  const pid = reg.json.id;
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: shop('x') })).status, 409);

  await call('PATCH', '/pharmacy', { token: owner, body: { status: 'verified', ownerId: 'x', isOpen: false } }); // status must be ignored
  const after = (await call('GET', '/pharmacy', { token: owner })).json;
  assert.equal(after.status, 'pending');
  assert.equal(after.isOpen, false);

  const s1 = await call('POST', '/stock', { token: owner, body: { name: 'নাপা ৫০০', genericName: 'প্যারাসিটামল', buyPrice: 38, sellPrice: 45, qty: 10, status: 'in' } });
  assert.equal(s1.status, 201);
  assert.equal(s1.json.sellPrice, 45);
  await call('POST', '/stock', { token: owner, body: { name: 'ওমিপ্রাজল ২০', status: 'out' } });

  let search = await call('POST', '/search', { token: patient, body: { names: ['নাপা'] } });
  assert.ok(!search.json.some((r: any) => r.pharmacyId === pid), 'unverified shop must be invisible to patients');
  assert.equal((await call('POST', '/requests', { token: patient, body: { pharmacyId: pid, patientName: 'করিম', items: [{ name: 'নাপা' }] } })).status, 404);

  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { body: { status: 'verified' } })).status, 401);
  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { admin: ADMIN, body: { status: 'verified' } })).status, 200);
  assert.equal((await fetch(`${base}/admin/pharmacies/${pid}/license`, { headers: { 'x-admin-key': ADMIN } })).status, 200);

  search = await call('POST', '/search', { token: patient, body: { names: ['নাপা', 'ওমিপ্রাজল', 'অজানা'] } });
  const st = Object.fromEntries(search.json.filter((r: any) => r.pharmacyId === pid).map((r: any) => [r.medicineName, r.status]));
  assert.deepEqual(st, { 'নাপা': 'in', 'ওমিপ্রাজল': 'out', 'অজানা': 'unknown' });
  assert.ok(!/buyPrice|sellPrice|qty|"45"|:45|:38/.test(JSON.stringify(search.json)), 'no price/qty leaks to patients');

  const rq = await call('POST', '/requests', { token: patient, body: { pharmacyId: pid, patientName: 'করিম', items: [{ name: 'নাপা', days: 10 }, { name: 'ওমিপ্রাজল', days: 7 }] } });
  assert.equal(rq.status, 201);
  const other = await login('pat2', 'patient');
  assert.equal((await call('GET', `/requests/${rq.json.id}`, { token: other })).status, 404);
  assert.equal((await call('POST', `/requests/${rq.json.id}/reply`, { token: patient, body: { items: ['yes', 'no'] } })).status, 404);

  const ownerList = await call('GET', '/requests?as=owner', { token: owner });
  assert.equal(ownerList.json.length, 1);
  assert.equal(ownerList.json[0].status, 'new');
  const rep = await call('POST', `/requests/${rq.json.id}/reply`, { token: owner, body: { items: ['yes', 'no'], message: 'বিকেলে আসুন' } });
  assert.equal(rep.status, 200);
  const mine = (await call('GET', '/requests', { token: patient })).json;
  assert.equal(mine[0].status, 'replied');
  assert.equal(mine[0].pharmacyName, 'রহমান ফার্মেসি');
  assert.deepEqual(mine[0].items.map((i: any) => i.availability), ['yes', 'no']);
  assert.equal((await call('POST', `/requests/${rq.json.id}/reply`, { token: owner, body: { items: ['yes'] } })).status, 400);

  const owner2 = await login('owner2', 'owner');
  assert.equal((await call('GET', '/stock', { token: owner2 })).status, 404);
  await call('POST', '/pharmacy', { token: owner2, body: shop('B') });
  assert.equal((await call('PATCH', `/stock/${s1.json.id}`, { token: owner2, body: { status: 'out' } })).status, 404);
  assert.equal((await call('GET', `/requests/${rq.json.id}`, { token: owner2 })).status, 404);
  assert.equal((await call('GET', '/stock', { token: owner2 })).json.length, 0);

  // stock status change is visible to patients immediately
  await call('PATCH', `/stock/${s1.json.id}`, { token: owner, body: { status: 'low' } });
  const again = await call('POST', '/search', { token: patient, body: { names: ['নাপা'] } });
  assert.equal(again.json.find((r: any) => r.pharmacyId === pid).status, 'low');
});

test('barcode: look up by scanned code, unique per pharmacy, owner-only', async () => {
  const owner = await login('owner6', 'owner');
  await call('POST', '/pharmacy', { token: owner, body: shop('F') });
  assert.equal((await call('GET', '/stock/barcode/8940001285711', { token: owner })).status, 404);
  const a = await call('POST', '/stock', { token: owner, body: { name: 'Ace Plus', barcode: '8940001285711', sellPrice: 12 } });
  assert.equal(a.status, 201);
  assert.equal(a.json.barcode, '8940001285711');
  const hit = await call('GET', '/stock/barcode/8940001285711', { token: owner });
  assert.equal(hit.status, 200);
  assert.equal(hit.json.name, 'Ace Plus');
  // same code twice in one shop is rejected, empty barcodes may repeat
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'Dup', barcode: '8940001285711' } })).status, 409);
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'NoCode1' } })).status, 201);
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'NoCode2', barcode: '' } })).status, 201);
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'Bad', barcode: 'abc' } })).status, 400);
  // another shop can use the same code, and cannot see ours
  const o2 = await login('owner7', 'owner');
  await call('POST', '/pharmacy', { token: o2, body: shop('G') });
  assert.equal((await call('GET', '/stock/barcode/8940001285711', { token: o2 })).status, 404);
  assert.equal((await call('POST', '/stock', { token: o2, body: { name: 'Mine', barcode: '8940001285711' } })).status, 201);
  const pat = await login('pat9', 'patient');
  assert.equal((await call('GET', '/stock/barcode/8940001285711', { token: pat })).status, 404); // a patient has no pharmacy, so no product list
  // patients' search never exposes the barcode
  assert.ok(!JSON.stringify((await call('POST', '/search', { token: pat, body: { names: ['Ace'] } })).json).includes('8940001285711'));
});

test('shared catalog: consensus from pharmacies, verified-only, identity only, admin override', async () => {
  const BC = '8940001999990';
  async function verifiedShop(sub: string, name: string) {
    const t = await login(sub, 'owner');
    const r = await call('POST', '/pharmacy', { token: t, body: shop(name) });
    await call('POST', `/admin/pharmacies/${r.json.id}/status`, { admin: ADMIN, body: { status: 'verified' } });
    return { t, id: r.json.id as string };
  }
  const a = await verifiedShop('cat-a', 'CatA');
  const b = await verifiedShop('cat-b', 'CatB');
  const c = await verifiedShop('cat-c', 'CatC');
  assert.equal((await call('GET', `/catalog/${BC}`, { token: a.t })).status, 404);

  // A names it; B reads A's suggestion (without learning who wrote it or any price)
  await call('POST', '/stock', { token: a.t, body: { name: 'Ace Plus', genericName: 'Paracetamol', form: 'Tablet', manufacturer: 'Square', barcode: BC, buyPrice: 5, sellPrice: 6 } });
  const hit = await call('GET', `/catalog/${BC}`, { token: b.t });
  assert.equal(hit.status, 200);
  assert.equal(hit.json.name, 'Ace Plus');
  assert.equal(hit.json.manufacturer, 'Square');
  assert.equal(hit.json.confirmations, 1);
  assert.ok(!/buyPrice|sellPrice|pharmacyId|CatA|\b5\b|\b6\b/.test(JSON.stringify(hit.json)), 'catalog must not leak prices or who wrote it');

  // B disagrees, C agrees with A (case/space-insensitive) -> A's name wins with 2 confirmations
  await call('POST', '/stock', { token: b.t, body: { name: 'Wrong name', barcode: BC } });
  await call('POST', '/stock', { token: c.t, body: { name: '  ace   PLUS ', barcode: BC } });
  const win = await call('GET', `/catalog/${BC}`, { token: a.t });
  assert.equal(win.json.confirmations, 2);
  assert.equal(win.json.name.trim().toLowerCase().replace(/\s+/g, ' '), 'ace plus');

  // editing your own entry updates it instead of adding a vote
  const mine = (await call('GET', `/stock/barcode/${BC}`, { token: b.t })).json;
  await call('PATCH', `/stock/${mine.id}`, { token: b.t, body: { name: 'Ace Plus' } });
  assert.equal((await call('GET', `/catalog/${BC}`, { token: a.t })).json.confirmations, 3);

  // unverified (pending) shops can read but never contribute
  const p = await login('cat-pending', 'owner');
  await call('POST', '/pharmacy', { token: p, body: shop('Pending') });
  assert.equal((await call('GET', `/catalog/${BC}`, { token: p })).status, 200);
  await call('POST', '/stock', { token: p, body: { name: 'Spam', barcode: '8940001999991' } });
  assert.equal((await call('GET', '/catalog/8940001999991', { token: a.t })).status, 404);

  // patients have no pharmacy, so no catalog access; bad barcode rejected
  const pat = await login('cat-pat', 'patient');
  assert.equal((await call('GET', `/catalog/${BC}`, { token: pat })).status, 404);
  assert.equal((await call('GET', '/catalog/abc', { token: a.t })).status, 400);

  // admin sees all entries and can pin a corrected name that overrides consensus
  assert.equal((await call('GET', `/admin/catalog/${BC}`, {})).status, 401);
  const view = await call('GET', `/admin/catalog/${BC}`, { admin: ADMIN });
  assert.equal(view.json.entries.length, 3);
  assert.equal((await call('PUT', `/admin/catalog/${BC}`, { admin: ADMIN, body: { name: 'Ace Plus 500 mg', form: 'Tablet' } })).status, 200);
  const pinned = await call('GET', `/catalog/${BC}`, { token: c.t });
  assert.equal(pinned.json.name, 'Ace Plus 500 mg');
  assert.equal(pinned.json.source, 'admin');
  assert.equal((await call('DELETE', `/admin/catalog/${BC}`, { admin: ADMIN })).status, 204);
  assert.equal((await call('GET', `/catalog/${BC}`, { token: c.t })).json.source, 'pharmacies');
});

test('khata payments are atomic, guarded, and mirror into the ledger', async () => {
  const owner = await login('owner3', 'owner');
  await call('POST', '/pharmacy', { token: owner, body: shop('C') });
  const k = (await call('POST', '/khata', { token: owner, body: { direction: 'receivable', partyName: 'আব্বাস', amount: 5000 } })).json;
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: 6000 } })).status, 400);
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: -1 } })).status, 400);
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: 2000 } })).json.paid, 2000);

  // two simultaneous payments of 2000 against the remaining 3000: only one may succeed
  const race = await Promise.all([1, 2].map(() => call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: 2000 } })));
  assert.deepEqual(race.map((r) => r.status).sort(), [200, 400]);
  const row = (await call('GET', '/khata?direction=receivable', { token: owner })).json[0];
  assert.equal(row.paid, 4000);

  const led = (await call('GET', '/ledger', { token: owner })).json;
  assert.equal(led.length, 2);
  assert.ok(led.every((l: any) => l.kind === 'income' && l.amount === 2000));
  const pay = (await call('POST', '/khata', { token: owner, body: { direction: 'payable', partyName: 'সরবরাহকারী', amount: 900 } })).json;
  await call('POST', `/khata/${pay.id}/pay`, { token: owner, body: { amount: 900 } });
  assert.equal((await call('GET', '/ledger', { token: owner })).json.filter((l: any) => l.kind === 'expense').length, 1);

  const other = await login('owner5', 'owner');
  await call('POST', '/pharmacy', { token: other, body: shop('E') });
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: other, body: { amount: 1 } })).status, 404);
});

test('input validation and size limits', async () => {
  const owner = await login('owner4', 'owner');
  const big = Buffer.alloc(800 * 1024, 1).toString('base64').slice(0, 999_000);
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: { ...shop('D'), licenseImage: big } })).status, 400);
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: { ...shop(''), } })).status, 400);
  await call('POST', '/pharmacy', { token: owner, body: shop('D') });
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'x', status: 'bogus' } })).status, 400);
  assert.equal((await call('POST', '/ledger', { token: owner, body: { kind: 'income', title: 't', amount: -5 } })).status, 400);
  assert.equal((await call('PATCH', '/pharmacy', { token: owner, body: { openFrom: '25:99' } })).status, 400);
  const res = await fetch(`${base}/stock`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${owner}` }, body: '{bad' });
  assert.equal(res.status, 400);
});

test('prescription parse: consent, draft sanitising, daily cap, no model configured', async () => {
  const fake = async () => ({
    readable: true, doctorName: ' Dr X ', problem: 'দাঁতে ব্যথা', visitDate: '2026-13-99x', nextVisitDate: '2026-10-20',
    medicines: [
      { name: 'Napa 500', strength: '500mg', form: 'tablet', morning: 1, noon: 0, night: 1, meal: 'after' as const, days: 5, note: null, uncertain: false },
      { name: 'Mystery', strength: null, form: null, morning: 1, noon: null, night: 1, meal: null, days: 9999, note: null, uncertain: false },
      { name: '  ', strength: null, form: null, morning: 1, noon: 1, night: 1, meal: null, days: 3, note: null, uncertain: false },
    ],
    tests: [{ name: 'OPG', uncertain: false }], advice: null,
  });
  const app = createApp({ db: prisma, verifyGoogle, jwtSecret: 'x'.repeat(40), readPrescription: fake, scanDailyLimit: 2 });
  const srv = await new Promise<Server>((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  const url = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
  try {
    const lg = async (sub: string) => (await (await fetch(`${url}/auth/google`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: `good:${sub}:${sub}` }) })).json() as any).token as string;
    const tok = await lg('scanner1');
    const post = async (body: unknown, token = tok) => {
      const r = await fetch(`${url}/prescriptions/parse`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
      return { status: r.status, json: await r.json() as any };
    };
    const img = Buffer.alloc(300, 7).toString('base64');
    assert.equal((await post({ mediaType: 'image/jpeg', image: img })).status, 400); // no consent
    assert.equal((await post({ consent: true, mediaType: 'image/gif', image: img })).status, 400);
    const ok = await post({ consent: true, mediaType: 'image/jpeg', image: img });
    assert.equal(ok.status, 200);
    const d = ok.json.draft;
    assert.equal(d.visitDate, null);                       // invalid date blanked
    assert.equal(d.medicines.length, 2);                   // nameless row dropped
    assert.equal(d.medicines[0].uncertain, false);         // fully read row stays confirmed-able
    assert.equal(d.medicines[1].uncertain, true);          // missing noon dose + absurd days -> must be confirmed
    assert.equal(d.medicines[1].days, null);
    assert.equal(ok.json.remainingToday, 1);
    assert.equal((await post({ consent: true, mediaType: 'image/png', image: img })).status, 200);
    assert.equal((await post({ consent: true, mediaType: 'image/png', image: img })).status, 429); // cap of 2
    const no = await fetch(`${url}/prescriptions/parse`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    assert.equal(no.status, 401);
  } finally { srv.close(); }
  // server without an API key configured
  const t2 = (await (await fetch(`${base}/auth/google`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: 'good:scanner2:scanner2' }) })).json() as any).token;
  const r = await call('POST', '/prescriptions/parse', { token: t2, body: { consent: true, mediaType: 'image/jpeg', image: Buffer.alloc(300, 7).toString('base64') } });
  assert.equal(r.status, 503);
});
