import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import express from 'express';
import { SignJWT, jwtVerify } from 'jose';
import { nowIso, tx } from './db.js';

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const bad = (m) => new HttpError(400, m);
const uid = () => crypto.randomUUID();
const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);

// ---- validation helpers
const str = (v, max, { req = true, name = 'field' } = {}) => {
  if (v == null || v === '') { if (req) throw bad(`${name} required`); return null; }
  if (typeof v !== 'string') throw bad(`${name} must be text`);
  const t = v.trim();
  if (req && !t) throw bad(`${name} required`);
  if (t.length > max) throw bad(`${name} too long`);
  return t || null;
};
const num = (v, { min = 0, req = false, name = 'number' } = {}) => {
  if (v == null || v === '') { if (req) throw bad(`${name} required`); return null; }
  const n = Number(v);
  if (!Number.isFinite(n) || n < min) throw bad(`${name} invalid`);
  return n;
};
const oneOf = (v, list, name) => { if (!list.includes(v)) throw bad(`${name} invalid`); return v; };
const isoDay = (v, name) => {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw bad(`${name} must be YYYY-MM-DD`);
  return v;
};
const hhmm = (v, name) => {
  if (typeof v !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(v)) throw bad(`${name} must be HH:MM`);
  return v;
};

// ---- row -> JSON (camelCase, same shapes the app uses)
const pharmacyJson = (r) => r && ({
  id: r.id, ownerId: r.owner_id, name: r.name, address: r.address, phone: r.phone, licenseNo: r.license_no,
  status: r.status, isOpen: !!r.is_open, openFrom: r.open_from, openTo: r.open_to, weeklyOff: r.weekly_off,
  notifyNew: !!r.notify_new, createdAt: r.created_at,
});
const stockJson = (r) => ({
  id: r.id, name: r.name, genericName: r.generic_name, form: r.form, qty: r.qty, unit: r.unit,
  buyPrice: r.buy_price, sellPrice: r.sell_price, expiry: r.expiry, batchNo: r.batch_no, status: r.status, updatedAt: r.updated_at,
});
const ledgerJson = (r) => ({ id: r.id, kind: r.kind, title: r.title, amount: r.amount, entryDate: r.entry_date, createdAt: r.created_at });
const khataJson = (r) => ({
  id: r.id, direction: r.direction, partyName: r.party_name, phone: r.phone, amount: r.amount, paid: r.paid, createdAt: r.created_at,
});

/**
 * @param {object} o
 * @param {import('node:sqlite').DatabaseSync} o.db
 * @param {(idToken: string) => Promise<{sub: string, email?: string, name?: string}>} o.verifyGoogle
 * @param {string} o.jwtSecret  >= 32 chars
 * @param {string} [o.adminKey] enables /admin routes when set (>= 16 chars)
 * @param {string} o.dataDir    where licence photos are stored
 */
export function createApp({ db, verifyGoogle, jwtSecret, adminKey, dataDir }) {
  if (!jwtSecret || jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');
  const key = new TextEncoder().encode(jwtSecret);
  const licDir = path.join(dataDir, 'licenses');
  fs.mkdirSync(licDir, { recursive: true });

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1); // behind Caddy
  app.use(express.json({ limit: '1.5mb' }));

  // ---- tiny in-memory rate limiter (per IP; resets per minute)
  const hits = new Map();
  setInterval(() => hits.clear(), 60_000).unref();
  const limit = (max) => (req, res, next) => {
    const k = `${req.ip}|${max}`;
    const n = (hits.get(k) ?? 0) + 1;
    hits.set(k, n);
    return n > max ? next(new HttpError(429, 'too many requests')) : next();
  };
  app.use(limit(600));

  app.get('/health', (_req, res) => res.json({ ok: true }));

  // ---- auth
  const issue = (user) => new SignJWT({ role: user.role ?? null })
    .setProtectedHeader({ alg: 'HS256' }).setSubject(user.id).setIssuedAt().setExpirationTime('60d').sign(key);
  const userJson = (u) => ({ id: u.id, email: u.email, name: u.name, role: u.role });

  app.post('/auth/google', limit(20), ah(async (req, res) => {
    const idToken = str(req.body?.idToken, 4096, { name: 'idToken' });
    let g;
    try { g = await verifyGoogle(idToken); } catch { throw new HttpError(401, 'invalid Google token'); }
    let u = db.prepare('SELECT * FROM users WHERE google_sub = ?').get(g.sub);
    if (!u) {
      const id = uid();
      db.prepare('INSERT INTO users (id, google_sub, email, name) VALUES (?,?,?,?)').run(id, g.sub, g.email ?? null, g.name ?? g.email ?? null);
      u = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
    }
    res.json({ token: await issue(u), user: userJson(u) });
  }));

  const auth = ah(async (req, _res) => {
    const h = req.get('authorization') ?? '';
    if (!h.startsWith('Bearer ')) throw new HttpError(401, 'sign in required');
    let sub;
    try { ({ payload: { sub } } = await jwtVerify(h.slice(7), key, { algorithms: ['HS256'] })); } catch { throw new HttpError(401, 'session expired'); }
    // Role is always read from the DB, never trusted from the token.
    const u = db.prepare('SELECT * FROM users WHERE id = ?').get(sub);
    if (!u) throw new HttpError(401, 'unknown user');
    req.user = u;
  });
  const authed = (req, res, next) => auth(req, res).then(() => next(), next);
  const role = (r) => (req, _res, next) => (req.user.role === r ? next() : next(new HttpError(403, `${r} account required`)));

  app.get('/me', authed, (req, res) => res.json(userJson(req.user)));

  app.post('/me/role', authed, (req, res) => {
    const r = oneOf(req.body?.role, ['patient', 'owner'], 'role');
    if (req.user.role) throw new HttpError(409, 'role already chosen'); // write-once
    db.prepare('UPDATE users SET role = ? WHERE id = ?').run(r, req.user.id);
    res.json(userJson({ ...req.user, role: r }));
  });

  // ---- owner: pharmacy
  const owner = [authed, role('owner')];
  const myPharmacy = (req) => db.prepare('SELECT * FROM pharmacies WHERE owner_id = ?').get(req.user.id);
  const needPharmacy = (req) => { const p = myPharmacy(req); if (!p) throw new HttpError(404, 'no pharmacy yet'); return p; };

  app.post('/pharmacy', ...owner, (req, res) => {
    if (myPharmacy(req)) throw new HttpError(409, 'pharmacy already registered');
    const b = req.body ?? {};
    const name = str(b.name, 120, { name: 'name' }), address = str(b.address, 300, { name: 'address' });
    const phone = str(b.phone, 30, { name: 'phone' }), licenseNo = str(b.licenseNo, 60, { name: 'licenseNo' });
    const img = str(b.licenseImage, 1_000_000, { name: 'licenseImage' });
    const bytes = Buffer.from(img, 'base64');
    if (bytes.length < 1000 || bytes.length > 700 * 1024) throw bad('licence photo must be under 700 KB');
    const id = uid();
    tx(db, () => db.prepare('INSERT INTO pharmacies (id, owner_id, name, address, phone, license_no) VALUES (?,?,?,?,?,?)')
      .run(id, req.user.id, name, address, phone, licenseNo));
    fs.writeFileSync(path.join(licDir, `${id}.img`), bytes);
    res.status(201).json(pharmacyJson(myPharmacy(req)));
  });

  app.get('/pharmacy', ...owner, (req, res) => res.json(pharmacyJson(myPharmacy(req))));

  app.patch('/pharmacy', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const b = req.body ?? {};
    const set = {};
    // `status` and ownership are deliberately not editable here.
    if ('name' in b) set.name = str(b.name, 120, { name: 'name' });
    if ('address' in b) set.address = str(b.address, 300, { name: 'address' });
    if ('phone' in b) set.phone = str(b.phone, 30, { name: 'phone' });
    if ('licenseNo' in b) set.license_no = str(b.licenseNo, 60, { name: 'licenseNo' });
    if ('isOpen' in b) set.is_open = b.isOpen ? 1 : 0;
    if ('notifyNew' in b) set.notify_new = b.notifyNew ? 1 : 0;
    if ('openFrom' in b) set.open_from = hhmm(b.openFrom, 'openFrom');
    if ('openTo' in b) set.open_to = hhmm(b.openTo, 'openTo');
    if ('weeklyOff' in b) set.weekly_off = str(b.weeklyOff, 100, { req: false });
    const cols = Object.keys(set);
    if (cols.length) db.prepare(`UPDATE pharmacies SET ${cols.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`).run(...cols.map((c) => set[c]), p.id);
    res.json(pharmacyJson(db.prepare('SELECT * FROM pharmacies WHERE id = ?').get(p.id)));
  });

  // ---- owner: stock (prices etc. are only ever returned here)
  const stockFields = (b, partial) => {
    const s = {};
    const has = (k) => !partial || k in b;
    if (has('name')) s.name = str(b.name, 160, { name: 'name' });
    if (has('genericName')) s.generic_name = str(b.genericName, 160, { req: false });
    if (has('form')) s.form = str(b.form, 40, { req: false });
    if (has('qty')) s.qty = num(b.qty, { name: 'qty' });
    if (has('unit')) s.unit = str(b.unit, 30, { req: false });
    if (has('buyPrice')) s.buy_price = num(b.buyPrice, { name: 'buyPrice' });
    if (has('sellPrice')) s.sell_price = num(b.sellPrice, { name: 'sellPrice' });
    if (has('expiry')) s.expiry = b.expiry == null ? null : isoDay(b.expiry, 'expiry');
    if (has('batchNo')) s.batch_no = str(b.batchNo, 60, { req: false });
    if (has('status')) s.status = oneOf(b.status ?? 'in', ['in', 'low', 'out'], 'status');
    return s;
  };

  app.get('/stock', ...owner, (req, res) => {
    const p = needPharmacy(req);
    res.json(db.prepare('SELECT * FROM stock WHERE pharmacy_id = ? ORDER BY name').all(p.id).map(stockJson));
  });
  app.post('/stock', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const s = stockFields(req.body ?? {}, false);
    const id = uid();
    const cols = Object.keys(s);
    db.prepare(`INSERT INTO stock (id, pharmacy_id, ${cols.join(', ')}) VALUES (?, ?, ${cols.map(() => '?').join(', ')})`).run(id, p.id, ...cols.map((c) => s[c]));
    res.status(201).json(stockJson(db.prepare('SELECT * FROM stock WHERE id = ?').get(id)));
  });
  app.patch('/stock/:id', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const s = stockFields(req.body ?? {}, true);
    const cols = Object.keys(s);
    if (!cols.length) throw bad('nothing to update');
    const r = db.prepare(`UPDATE stock SET ${cols.map((c) => `${c} = ?`).join(', ')}, updated_at = ? WHERE id = ? AND pharmacy_id = ?`)
      .run(...cols.map((c) => s[c]), nowIso(), req.params.id, p.id);
    if (!r.changes) throw new HttpError(404, 'not found');
    res.json(stockJson(db.prepare('SELECT * FROM stock WHERE id = ?').get(req.params.id)));
  });
  app.delete('/stock/:id', ...owner, (req, res) => {
    const p = needPharmacy(req);
    db.prepare('DELETE FROM stock WHERE id = ? AND pharmacy_id = ?').run(req.params.id, p.id);
    res.status(204).end();
  });

  // ---- patient: search (only name + in/low/out; never prices/quantities)
  const patient = [authed, role('patient')];
  app.post('/search', ...patient, limit(60), (req, res) => {
    const names = req.body?.names;
    if (!Array.isArray(names) || !names.length || names.length > 20) throw bad('names must be 1-20 items');
    const qs = names.map((n, i) => str(n, 120, { name: `names[${i}]` }));
    const phs = db.prepare("SELECT * FROM pharmacies WHERE status = 'verified' ORDER BY name LIMIT 100").all();
    const rank = { in: 3, low: 2, out: 1 };
    const likeEsc = (s) => `%${s.toLowerCase().replace(/[\\%_]/g, '\\$&')}%`;
    const find = db.prepare(`SELECT status FROM stock WHERE pharmacy_id = ?
      AND (lower(name) LIKE ? ESCAPE '\\' OR lower(coalesce(generic_name,'')) LIKE ? ESCAPE '\\')`);
    const upd = db.prepare('SELECT max(updated_at) AS u FROM stock WHERE pharmacy_id = ?');
    const out = [];
    for (const p of phs) {
      const updatedAt = upd.get(p.id).u;
      for (const q of qs) {
        let best = 'unknown';
        for (const r of find.all(p.id, likeEsc(q), likeEsc(q))) if ((rank[r.status] ?? 0) > (rank[best] ?? 0)) best = r.status;
        out.push({ pharmacyId: p.id, pharmacyName: p.name, address: p.address, phone: p.phone, isOpen: !!p.is_open, medicineName: q, status: best, updatedAt });
      }
    }
    res.json(out);
  });

  // ---- requests
  const itemsOf = (id) => db.prepare('SELECT name, days, availability FROM request_items WHERE request_id = ? ORDER BY idx').all(id);
  const reqJson = (r, withShop = false) => ({
    id: r.id, pharmacyId: r.pharmacy_id, patientId: r.patient_id, patientName: r.patient_name, status: r.status,
    replyMessage: r.reply_message, repliedAt: r.replied_at, createdAt: r.created_at, items: itemsOf(r.id),
    ...(withShop ? { pharmacyName: r.ph_name, pharmacyPhone: r.ph_phone } : {}),
  });

  app.post('/requests', ...patient, limit(60), (req, res) => {
    const b = req.body ?? {};
    const ph = db.prepare("SELECT id FROM pharmacies WHERE id = ? AND status = 'verified'").get(b.pharmacyId);
    if (!ph) throw new HttpError(404, 'pharmacy not available');
    const patientName = str(b.patientName, 80, { name: 'patientName' });
    if (!Array.isArray(b.items) || !b.items.length || b.items.length > 30) throw bad('items must be 1-30');
    const items = b.items.map((i, k) => ({ name: str(i?.name, 120, { name: `items[${k}].name` }), days: Math.min(num(i?.days, { name: 'days' }) ?? 0, 365) }));
    const id = uid();
    tx(db, () => {
      db.prepare('INSERT INTO requests (id, pharmacy_id, patient_id, patient_name) VALUES (?,?,?,?)').run(id, ph.id, req.user.id, patientName);
      const ins = db.prepare('INSERT INTO request_items (request_id, idx, name, days) VALUES (?,?,?,?)');
      items.forEach((it, k) => ins.run(id, k, it.name, it.days));
    });
    res.status(201).json({ id });
  });

  app.get('/requests', authed, (req, res) => {
    let rows;
    if (req.user.role === 'owner') {
      const p = needPharmacy(req);
      rows = db.prepare('SELECT * FROM requests WHERE pharmacy_id = ? ORDER BY created_at DESC LIMIT 300').all(p.id).map((r) => reqJson(r));
    } else {
      rows = db.prepare(`SELECT r.*, p.name AS ph_name, p.phone AS ph_phone FROM requests r JOIN pharmacies p ON p.id = r.pharmacy_id
        WHERE r.patient_id = ? ORDER BY r.created_at DESC LIMIT 100`).all(req.user.id).map((r) => reqJson(r, true));
    }
    res.json(rows);
  });

  const loadRequest = (req) => {
    const r = db.prepare('SELECT * FROM requests WHERE id = ?').get(req.params.id);
    if (!r) throw new HttpError(404, 'not found');
    const mine = r.patient_id === req.user.id;
    const shop = req.user.role === 'owner' && db.prepare('SELECT 1 FROM pharmacies WHERE id = ? AND owner_id = ?').get(r.pharmacy_id, req.user.id);
    if (!mine && !shop) throw new HttpError(404, 'not found'); // don't reveal existence
    return r;
  };
  app.get('/requests/:id', authed, (req, res) => res.json(reqJson(loadRequest(req))));

  app.post('/requests/:id/reply', ...owner, (req, res) => {
    const r = loadRequest(req);
    const avail = req.body?.items;
    const list = itemsOf(r.id);
    if (!Array.isArray(avail) || avail.length !== list.length) throw bad('one availability per item required');
    const msg = str(req.body?.message, 500, { req: false });
    tx(db, () => {
      const up = db.prepare('UPDATE request_items SET availability = ? WHERE request_id = ? AND idx = ?');
      avail.forEach((a, k) => up.run(oneOf(a, ['pending', 'yes', 'no'], 'availability'), r.id, k));
      db.prepare("UPDATE requests SET status = 'replied', reply_message = ?, replied_at = ? WHERE id = ?").run(msg, nowIso(), r.id);
    });
    res.json(reqJson(db.prepare('SELECT * FROM requests WHERE id = ?').get(r.id)));
  });

  // ---- owner books
  app.get('/ledger', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const from = req.query.from ? isoDay(String(req.query.from), 'from') : '0000-01-01';
    res.json(db.prepare('SELECT * FROM ledger WHERE pharmacy_id = ? AND entry_date >= ? ORDER BY entry_date DESC, created_at DESC LIMIT 1000').all(p.id, from).map(ledgerJson));
  });
  app.post('/ledger', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const b = req.body ?? {};
    const id = uid();
    db.prepare('INSERT INTO ledger (id, pharmacy_id, kind, title, amount, entry_date) VALUES (?,?,?,?,?,?)').run(
      id, p.id, oneOf(b.kind, ['income', 'expense'], 'kind'), str(b.title, 160, { name: 'title' }),
      num(b.amount, { req: true, name: 'amount' }), b.entryDate ? isoDay(b.entryDate, 'entryDate') : new Date().toISOString().slice(0, 10));
    res.status(201).json(ledgerJson(db.prepare('SELECT * FROM ledger WHERE id = ?').get(id)));
  });
  app.delete('/ledger/:id', ...owner, (req, res) => {
    const p = needPharmacy(req);
    db.prepare('DELETE FROM ledger WHERE id = ? AND pharmacy_id = ?').run(req.params.id, p.id);
    res.status(204).end();
  });

  app.get('/khata', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const dir = oneOf(req.query.direction ?? 'receivable', ['receivable', 'payable'], 'direction');
    res.json(db.prepare('SELECT * FROM khata WHERE pharmacy_id = ? AND direction = ? ORDER BY created_at').all(p.id, dir).map(khataJson));
  });
  app.post('/khata', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const b = req.body ?? {};
    const id = uid();
    const amount = num(b.amount, { req: true, name: 'amount' });
    if (amount <= 0) throw bad('amount must be positive');
    db.prepare('INSERT INTO khata (id, pharmacy_id, direction, party_name, phone, amount) VALUES (?,?,?,?,?,?)').run(
      id, p.id, oneOf(b.direction, ['receivable', 'payable'], 'direction'), str(b.partyName, 120, { name: 'partyName' }), str(b.phone, 30, { req: false }), amount);
    res.status(201).json(khataJson(db.prepare('SELECT * FROM khata WHERE id = ?').get(id)));
  });
  // Recording a payment also books it as income/expense, atomically.
  app.post('/khata/:id/pay', ...owner, (req, res) => {
    const p = needPharmacy(req);
    const amt = num(req.body?.amount, { req: true, name: 'amount' });
    const out = tx(db, () => {
      const k = db.prepare('SELECT * FROM khata WHERE id = ? AND pharmacy_id = ?').get(req.params.id, p.id);
      if (!k) throw new HttpError(404, 'not found');
      const left = k.amount - k.paid;
      if (amt <= 0 || amt > left + 1e-9) throw bad(`amount must be between 0 and ${left}`);
      db.prepare('UPDATE khata SET paid = paid + ? WHERE id = ?').run(amt, k.id);
      const rec = k.direction === 'receivable';
      db.prepare('INSERT INTO ledger (id, pharmacy_id, kind, title, amount, entry_date) VALUES (?,?,?,?,?,?)').run(
        uid(), p.id, rec ? 'income' : 'expense', `${rec ? 'বাকি আদায়' : 'পরিশোধ'}: ${k.party_name}`, amt, new Date().toISOString().slice(0, 10));
      return db.prepare('SELECT * FROM khata WHERE id = ?').get(k.id);
    });
    res.json(khataJson(out));
  });

  // ---- admin (verification). Disabled unless ADMIN_KEY is configured.
  if (adminKey) {
    if (adminKey.length < 16) throw new Error('ADMIN_KEY must be at least 16 characters');
    const adminAuth = (req, _res, next) => {
      const a = Buffer.from(req.get('x-admin-key') ?? '');
      const b = Buffer.from(adminKey);
      return a.length === b.length && crypto.timingSafeEqual(a, b) ? next() : next(new HttpError(401, 'admin key required'));
    };
    app.get('/admin/pharmacies', limit(30), adminAuth, (req, res) => {
      const st = req.query.status ? oneOf(String(req.query.status), ['pending', 'verified', 'rejected'], 'status') : null;
      const rows = st ? db.prepare('SELECT * FROM pharmacies WHERE status = ? ORDER BY created_at').all(st) : db.prepare('SELECT * FROM pharmacies ORDER BY created_at').all();
      res.json(rows.map(pharmacyJson));
    });
    app.get('/admin/pharmacies/:id/license', limit(30), adminAuth, (req, res) => {
      if (!/^[0-9a-f-]{36}$/.test(req.params.id)) throw bad('bad id');
      const f = path.join(licDir, `${req.params.id}.img`);
      if (!fs.existsSync(f)) throw new HttpError(404, 'no licence photo');
      res.type('image/jpeg').send(fs.readFileSync(f));
    });
    app.post('/admin/pharmacies/:id/status', limit(30), adminAuth, (req, res) => {
      const st = oneOf(req.body?.status, ['pending', 'verified', 'rejected'], 'status');
      const r = db.prepare('UPDATE pharmacies SET status = ? WHERE id = ?').run(st, req.params.id);
      if (!r.changes) throw new HttpError(404, 'not found');
      res.json({ ok: true });
    });
  }

  app.use((_req, _res, next) => next(new HttpError(404, 'not found')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'request too large' });
    if (err instanceof SyntaxError) return res.status(400).json({ error: 'invalid JSON' });
    if (/constraint/i.test(err?.message ?? '')) return res.status(400).json({ error: 'invalid data' });
    console.error(err);
    res.status(500).json({ error: 'server error' });
  });
  return app;
}
