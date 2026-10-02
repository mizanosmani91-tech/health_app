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

test('role is write-once and enforced per route', async () => {
  const t = await login('u1', 'patient');
  assert.equal((await call('POST', '/me/role', { token: t, body: { role: 'owner' } })).status, 409);
  assert.equal((await call('GET', '/stock', { token: t })).status, 403);
  const o = await login('u2', 'owner');
  assert.equal((await call('POST', '/search', { token: o, body: { names: ['x'] } })).status, 403);
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
  assert.deepEqual(search.json, []);
  assert.equal((await call('POST', '/requests', { token: patient, body: { pharmacyId: pid, patientName: 'করিম', items: [{ name: 'নাপা' }] } })).status, 404);

  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { body: { status: 'verified' } })).status, 401);
  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { admin: ADMIN, body: { status: 'verified' } })).status, 200);
  assert.equal((await fetch(`${base}/admin/pharmacies/${pid}/license`, { headers: { 'x-admin-key': ADMIN } })).status, 200);

  search = await call('POST', '/search', { token: patient, body: { names: ['নাপা', 'ওমিপ্রাজল', 'অজানা'] } });
  const st = Object.fromEntries(search.json.map((r: any) => [r.medicineName, r.status]));
  assert.deepEqual(st, { 'নাপা': 'in', 'ওমিপ্রাজল': 'out', 'অজানা': 'unknown' });
  assert.ok(!/buyPrice|sellPrice|qty|"45"|:45|:38/.test(JSON.stringify(search.json)), 'no price/qty leaks to patients');

  const rq = await call('POST', '/requests', { token: patient, body: { pharmacyId: pid, patientName: 'করিম', items: [{ name: 'নাপা', days: 10 }, { name: 'ওমিপ্রাজল', days: 7 }] } });
  assert.equal(rq.status, 201);
  const other = await login('pat2', 'patient');
  assert.equal((await call('GET', `/requests/${rq.json.id}`, { token: other })).status, 404);
  assert.equal((await call('POST', `/requests/${rq.json.id}/reply`, { token: patient, body: { items: ['yes', 'no'] } })).status, 403);

  const ownerList = await call('GET', '/requests', { token: owner });
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
  assert.equal(again.json[0].status, 'low');
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
  assert.equal((await call('GET', '/stock/barcode/8940001285711', { token: pat })).status, 403);
  // patients' search never exposes the barcode
  assert.ok(!JSON.stringify((await call('POST', '/search', { token: pat, body: { names: ['Ace'] } })).json).includes('8940001285711'));
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
