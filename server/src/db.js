import { DatabaseSync } from 'node:sqlite';

/** Opens (and migrates) the SQLite database. Pass ':memory:' in tests. */
export function openDb(file) {
  const db = new DatabaseSync(file);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    PRAGMA busy_timeout = 5000;

    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, google_sub TEXT NOT NULL UNIQUE, email TEXT, name TEXT,
      role TEXT CHECK (role IN ('patient','owner')),
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    CREATE TABLE IF NOT EXISTS pharmacies (
      id TEXT PRIMARY KEY, owner_id TEXT NOT NULL UNIQUE REFERENCES users(id),
      name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, license_no TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','verified','rejected')),
      is_open INTEGER NOT NULL DEFAULT 1, open_from TEXT NOT NULL DEFAULT '09:00', open_to TEXT NOT NULL DEFAULT '22:00',
      weekly_off TEXT, notify_new INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    CREATE TABLE IF NOT EXISTS stock (
      id TEXT PRIMARY KEY, pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
      name TEXT NOT NULL, generic_name TEXT, form TEXT, qty REAL, unit TEXT,
      buy_price REAL, sell_price REAL, expiry TEXT, batch_no TEXT,
      status TEXT NOT NULL DEFAULT 'in' CHECK (status IN ('in','low','out')),
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    CREATE INDEX IF NOT EXISTS stock_ph ON stock(pharmacy_id);
    CREATE TABLE IF NOT EXISTS requests (
      id TEXT PRIMARY KEY, pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
      patient_id TEXT NOT NULL REFERENCES users(id), patient_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','replied')),
      reply_message TEXT, replied_at TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    CREATE INDEX IF NOT EXISTS req_ph ON requests(pharmacy_id);
    CREATE INDEX IF NOT EXISTS req_pt ON requests(patient_id);
    CREATE TABLE IF NOT EXISTS request_items (
      request_id TEXT NOT NULL REFERENCES requests(id) ON DELETE CASCADE, idx INTEGER NOT NULL,
      name TEXT NOT NULL, days INTEGER NOT NULL DEFAULT 0,
      availability TEXT NOT NULL DEFAULT 'pending' CHECK (availability IN ('pending','yes','no')),
      PRIMARY KEY (request_id, idx)
    );
    CREATE TABLE IF NOT EXISTS ledger (
      id TEXT PRIMARY KEY, pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('income','expense')), title TEXT NOT NULL,
      amount REAL NOT NULL CHECK (amount >= 0), entry_date TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
    CREATE INDEX IF NOT EXISTS ledger_ph ON ledger(pharmacy_id, entry_date);
    CREATE TABLE IF NOT EXISTS khata (
      id TEXT PRIMARY KEY, pharmacy_id TEXT NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
      direction TEXT NOT NULL CHECK (direction IN ('receivable','payable')),
      party_name TEXT NOT NULL, phone TEXT,
      amount REAL NOT NULL CHECK (amount > 0), paid REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
      CHECK (paid >= 0 AND paid <= amount)
    );
    CREATE INDEX IF NOT EXISTS khata_ph ON khata(pharmacy_id, direction);
  `);
  return db;
}

export const nowIso = () => new Date().toISOString();

export function tx(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
