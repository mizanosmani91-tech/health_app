# Health Diary API

TypeScript + Express + Prisma + PostgreSQL API (same stack as `attendify`) for the pharmacy side of the app (accounts/roles, pharmacies, stock status,
patient requests, owner books). Patients' health records are **not** stored here.

- Auth: the app signs in with Google natively and sends the Google ID token to `POST /auth/google`;
  the server verifies it against Google's keys (audience = your web client id) and issues its own 60-day session token.
- Privacy: patients only ever receive `in/low/out` per medicine (`POST /search`); prices, quantities and batches are owner-only.
- Verification of pharmacies is manual (see below). Until then a shop is invisible to patients.

## Run tests
```sh
cd server && npm ci
# needs an empty Postgres database whose name contains "test" (it is wiped on every run):
TEST_DATABASE_URL=postgresql://user:pw@localhost:5432/healthdiary_test npm test
```

## Deploy (Ubuntu VPS)
```sh
git clone https://github.com/mizanosmani91-tech/health_app && cd health_app
git checkout claude/family-health-tracker-oa9nmf
sudo bash server/deploy/setup.sh vps-XXXX.vps.ovh.ca <google-web-client-id>.apps.googleusercontent.com
```
It installs Node, PostgreSQL, the service (systemd, auto-restart), Caddy with automatic HTTPS, runs the migrations, and sets a daily `pg_dump` backup.
Add `--firewall` as a third argument to also enable ufw (22/80/443) — only if nothing else on the box uses other ports.

## Verify a pharmacy
```sh
KEY=$(sudo grep ADMIN_KEY /etc/health-diary.env | cut -d= -f2)
curl -H "x-admin-key: $KEY" "https://DOMAIN/admin/pharmacies?status=pending"          # list
curl -H "x-admin-key: $KEY" https://DOMAIN/admin/pharmacies/ID/license -o lic.jpg    # look at the licence photo
curl -X POST -H "x-admin-key: $KEY" -H 'content-type: application/json' -d '{"status":"verified"}' https://DOMAIN/admin/pharmacies/ID/status
```

## Backups & updates
- Backups: `/var/backups/health-diary` (14 days, `pg_restore`-able). **Copy them off the server** — a VPS disk failure otherwise loses everything.
- Update: `git pull && sudo bash server/deploy/setup.sh DOMAIN CLIENT_ID` (rebuilds, runs new migrations, keeps secrets and data).
- Logs: `journalctl -u health-diary -f`

## Shared medicine catalog
Verified pharmacies that save a stock item with a barcode contribute its identity (name / generic / form / maker) to a shared catalog.
Other pharmacies scanning the same barcode get it pre-filled (`GET /catalog/:barcode`). Prices, quantities and which shop stocks what are never shared.
The shown name is the one most distinct pharmacies agree on. To correct a bad entry:
```sh
KEY=$(sudo grep ADMIN_KEY /etc/health-diary.env | cut -d= -f2)
curl -H "x-admin-key: $KEY" https://DOMAIN/admin/catalog/8940001285711                     # what pharmacies wrote
curl -X PUT -H "x-admin-key: $KEY" -H 'content-type: application/json' -d '{"name":"Ace Plus 500 mg","genericName":"Paracetamol","form":"Tablet","manufacturer":"Square"}' https://DOMAIN/admin/catalog/8940001285711   # pin a corrected entry
curl -X DELETE -H "x-admin-key: $KEY" https://DOMAIN/admin/catalog/8940001285711           # remove the pin
```

## প্রেসক্রিপশনের ছবি পড়া (ঐচ্ছিক)

`POST /prescriptions/parse` — ছবি থেকে শুধু একটা **খসড়া** ফেরত দেয় (ছবি/ফলাফল সার্ভারে জমা হয় না)। চালু করতে `/etc/health-diary.env`-এ
`ANTHROPIC_API_KEY=...` বসিয়ে `systemctl restart health-diary` করুন (কী কখনো রিপোতে/চ্যাটে নয়)। না থাকলে এন্ডপয়েন্ট 503 দেয়।
`SCAN_DAILY_LIMIT` (ডিফল্ট ১০) প্রতি ব্যবহারকারীর দৈনিক সীমা, `ANTHROPIC_MODEL` ঐচ্ছিক। `update.sh` নতুন মাইগ্রেশন নিজেই চালায়।
