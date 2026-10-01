import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { openDb } from '../src/db.js';

let server, base, dir;
const ADMIN = 'admin-key-1234567890';
// "Google" for tests: the token string is the user's identity.
const verifyGoogle = async (t) => {
  if (!t.startsWith('good:')) throw new Error('bad');
  const [, sub, name] = t.split(':');
  return { sub, email: `${sub}@x.com`, name };
};

before(async () => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hd-'));
  const app = createApp({ db: openDb(':memory:'), verifyGoogle, jwtSecret: 'x'.repeat(40), adminKey: ADMIN, dataDir: dir });
  await new Promise((r) => { server = app.listen(0, '127.0.0.1', r); });
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { server.close(); fs.rmSync(dir, { recursive: true, force: true }); });

async function call(method, url, { token, body, admin } = {}) {
  const res = await fetch(base + url, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...(admin ? { 'x-admin-key': admin } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, json };
}
async function login(sub, role) {
  const r = await call('POST', '/auth/google', { body: { idToken: `good:${sub}:${sub}` } });
  assert.equal(r.status, 200);
  if (role) assert.equal((await call('POST', '/me/role', { token: r.json.token, body: { role } })).status, 200);
  return r.json.token;
}
const photo = Buffer.alloc(5000, 7).toString('base64');

test('rejects bad Google token and unauthenticated calls', async () => {
  assert.equal((await call('POST', '/auth/google', { body: { idToken: 'evil' } })).status, 401);
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
  const reg = await call('POST', '/pharmacy', { token: owner, body: { name: 'রহমান ফার্মেসি', address: 'মিরপুর', phone: '017', licenseNo: 'L1', licenseImage: photo } });
  assert.equal(reg.status, 201);
  assert.equal(reg.json.status, 'pending');
  const pid = reg.json.id;
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: { name: 'x', address: 'y', phone: '1', licenseNo: 'L', licenseImage: photo } })).status, 409);

  // owner can't self-verify
  await call('PATCH', '/pharmacy', { token: owner, body: { status: 'verified', ownerId: 'x', isOpen: false } });
  assert.equal((await call('GET', '/pharmacy', { token: owner })).json.status, 'pending');

  const s1 = await call('POST', '/stock', { token: owner, body: { name: 'নাপা ৫০০', genericName: 'প্যারাসিটামল', buyPrice: 38, sellPrice: 45, qty: 10, status: 'in' } });
  assert.equal(s1.status, 201);
  await call('POST', '/stock', { token: owner, body: { name: 'ওমিপ্রাজল ২০', status: 'out' } });

  // unverified shops are invisible to patients
  let search = await call('POST', '/search', { token: patient, body: { names: ['নাপা'] } });
  assert.deepEqual(search.json, []);
  assert.equal((await call('POST', '/requests', { token: patient, body: { pharmacyId: pid, patientName: 'করিম', items: [{ name: 'নাপা' }] } })).status, 404);

  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { body: { status: 'verified' } })).status, 401);
  assert.equal((await call('POST', `/admin/pharmacies/${pid}/status`, { admin: ADMIN, body: { status: 'verified' } })).status, 200);
  const lic = await fetch(`${base}/admin/pharmacies/${pid}/license`, { headers: { 'x-admin-key': ADMIN } });
  assert.equal(lic.status, 200);

  search = await call('POST', '/search', { token: patient, body: { names: ['নাপা', 'ওমিপ্রাজল', 'অজানা'] } });
  const st = Object.fromEntries(search.json.map((r) => [r.medicineName, r.status]));
  assert.deepEqual(st, { 'নাপা': 'in', 'ওমিপ্রাজল': 'out', 'অজানা': 'unknown' });
  assert.ok(!JSON.stringify(search.json).match(/buyPrice|sellPrice|qty|45|38/), 'no price/qty leaks to patients');

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
  assert.deepEqual(mine[0].items.map((i) => i.availability), ['yes', 'no']);
  assert.equal((await call('POST', `/requests/${rq.json.id}/reply`, { token: owner, body: { items: ['yes'] } })).status, 400);

  // another owner can't touch this shop's stock or requests
  const owner2 = await login('owner2', 'owner');
  assert.equal((await call('GET', '/stock', { token: owner2 })).status, 404); // no pharmacy yet
  await call('POST', '/pharmacy', { token: owner2, body: { name: 'B', address: 'b', phone: '2', licenseNo: 'L2', licenseImage: photo } });
  assert.equal((await call('PATCH', `/stock/${s1.json.id}`, { token: owner2, body: { status: 'out' } })).status, 404);
  assert.equal((await call('GET', `/requests/${rq.json.id}`, { token: owner2 })).status, 404);
  assert.equal((await call('GET', '/stock', { token: owner2 })).json.length, 0);
});

test('khata payments are atomic and mirror into the ledger', async () => {
  const owner = await login('owner3', 'owner');
  await call('POST', '/pharmacy', { token: owner, body: { name: 'C', address: 'c', phone: '3', licenseNo: 'L3', licenseImage: photo } });
  const k = (await call('POST', '/khata', { token: owner, body: { direction: 'receivable', partyName: 'আব্বাস', amount: 5000 } })).json;
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: 6000 } })).status, 400);
  assert.equal((await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: -1 } })).status, 400);
  const paid = await call('POST', `/khata/${k.id}/pay`, { token: owner, body: { amount: 2000 } });
  assert.equal(paid.json.paid, 2000);
  const led = (await call('GET', '/ledger', { token: owner })).json;
  assert.equal(led.length, 1);
  assert.equal(led[0].kind, 'income');
  assert.equal(led[0].amount, 2000);
  const pay = (await call('POST', '/khata', { token: owner, body: { direction: 'payable', partyName: 'সরবরাহকারী', amount: 900 } })).json;
  await call('POST', `/khata/${pay.id}/pay`, { token: owner, body: { amount: 900 } });
  assert.equal((await call('GET', '/ledger', { token: owner })).json.filter((l) => l.kind === 'expense').length, 1);
  assert.equal((await call('GET', '/khata?direction=receivable', { token: owner })).json.length, 1);
});

test('input validation and size limits', async () => {
  const owner = await login('owner4', 'owner');
  const big = Buffer.alloc(800 * 1024, 1).toString('base64').slice(0, 999_000);
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: { name: 'D', address: 'd', phone: '4', licenseNo: 'L4', licenseImage: big } })).status, 400);
  assert.equal((await call('POST', '/pharmacy', { token: owner, body: { name: '', address: 'd', phone: '4', licenseNo: 'L4', licenseImage: photo } })).status, 400);
  await call('POST', '/pharmacy', { token: owner, body: { name: 'D', address: 'd', phone: '4', licenseNo: 'L4', licenseImage: photo } });
  assert.equal((await call('POST', '/stock', { token: owner, body: { name: 'x', status: 'bogus' } })).status, 400);
  assert.equal((await call('POST', '/ledger', { token: owner, body: { kind: 'income', title: 't', amount: -5 } })).status, 400);
  assert.equal((await call('PATCH', '/pharmacy', { token: owner, body: { openFrom: '25:99' } })).status, 400);
  const res = await fetch(`${base}/stock`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${owner}` }, body: '{bad' });
  assert.equal(res.status, 400);
});
