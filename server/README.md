# Health Diary API

Small Node 22 + SQLite API for the pharmacy side of the app (accounts/roles, pharmacies, stock status,
patient requests, owner books). Patients' health records are **not** stored here.

- Auth: the app signs in with Google natively and sends the Google ID token to `POST /auth/google`;
  the server verifies it against Google's keys (audience = your web client id) and issues its own 60-day session token.
- Privacy: patients only ever receive `in/low/out` per medicine (`POST /search`); prices, quantities and batches are owner-only.
- Verification of pharmacies is manual (see below). Until then a shop is invisible to patients.

## Run tests
```sh
cd server && npm ci && npm test
```

## Deploy (Ubuntu VPS)
```sh
git clone https://github.com/mizanosmani91-tech/health_app && cd health_app
git checkout claude/family-health-tracker-oa9nmf
sudo bash server/deploy/setup.sh vps-XXXX.vps.ovh.ca <google-web-client-id>.apps.googleusercontent.com
```
It installs Node, the service (systemd, auto-restart), Caddy with automatic HTTPS, and a daily backup.
Add `--firewall` as a third argument to also enable ufw (22/80/443) — only if nothing else on the box uses other ports.

## Verify a pharmacy
```sh
KEY=$(sudo grep ADMIN_KEY /etc/health-diary.env | cut -d= -f2)
curl -H "x-admin-key: $KEY" https://DOMAIN/admin/pharmacies?status=pending          # list
curl -H "x-admin-key: $KEY" https://DOMAIN/admin/pharmacies/ID/license -o lic.jpg    # look at the licence photo
curl -X POST -H "x-admin-key: $KEY" -H 'content-type: application/json' -d '{"status":"verified"}' https://DOMAIN/admin/pharmacies/ID/status
```

## Backups & updates
- Backups: `/var/lib/health-diary/backups` (14 days). **Copy them off the server** — a VPS disk failure otherwise loses everything.
- Update: `git pull && sudo bash server/deploy/setup.sh DOMAIN CLIENT_ID` (keeps secrets and data).
- Logs: `journalctl -u health-diary -f`
