#!/usr/bin/env bash
# Installs the Health Diary API on an Ubuntu VPS: Node 22, PostgreSQL, the app (systemd), HTTPS (Caddy, or an nginx vhost + certbot if nginx already serves your other sites),
# and daily database backups. Safe to re-run (updates code, runs new migrations, keeps secrets and data).
#
#   git clone https://github.com/mizanosmani91-tech/health_app && cd health_app
#   git checkout claude/family-health-tracker-oa9nmf
#   sudo bash server/deploy/setup.sh <domain> <google-web-client-id> [--firewall]
#
# <domain>  e.g. vps-2976817d.vps.ovh.ca (must resolve to this server; ports 80/443 reachable)
set -euo pipefail

DOMAIN="${1:-}"; CLIENT_ID="${2:-}"; FIREWALL="${3:-}"
[[ -n "$DOMAIN" && -n "$CLIENT_ID" ]] || { echo "usage: sudo bash $0 <domain> <google-web-client-id> [--firewall]"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/health-diary
BACKUPS=/var/backups/health-diary
ENVF=/etc/health-diary.env
export DEBIAN_FRONTEND=noninteractive

echo "==> packages"
apt-get update -y
apt-get install -y curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https rsync openssl postgresql postgresql-client

need_node=1
if command -v node >/dev/null; then
  node -e 'process.exit(Number(process.versions.node.split(".")[0])>=20?0:1)' && need_node=0 || true
fi
if [[ $need_node -eq 1 ]]; then
  echo "==> installing Node 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# If something (e.g. nginx for your other apps) already owns ports 80/443, add a vhost there instead of Caddy.
USE_NGINX=0
if command -v nginx >/dev/null && ss -tln | grep -qE ':(80|443)\s'; then USE_NGINX=1; fi

if [[ $USE_NGINX -eq 0 ]] && ! command -v caddy >/dev/null; then
  echo "==> installing Caddy"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "==> config ($ENVF)"
if [[ ! -f "$ENVF" ]]; then
  DBPASS="$(openssl rand -hex 24)"
  umask 077
  cat > "$ENVF" <<ENV
PORT=8787
DATABASE_URL=postgresql://healthdiary:${DBPASS}@127.0.0.1:5432/healthdiary?schema=public
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_KEY=$(openssl rand -hex 24)
GOOGLE_CLIENT_IDS=$CLIENT_ID
ENV
  su postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE ROLE healthdiary LOGIN PASSWORD '${DBPASS}'\"" || true
  su postgres -c "psql -v ON_ERROR_STOP=1 -c \"CREATE DATABASE healthdiary OWNER healthdiary\"" || true
else
  sed -i "s|^GOOGLE_CLIENT_IDS=.*|GOOGLE_CLIENT_IDS=$CLIENT_ID|" "$ENVF"
fi
id -u hd >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin hd
chown root:hd "$ENVF"; chmod 640 "$ENVF"

echo "==> app code, build, migrations"
mkdir -p "$APP"
rsync -a --delete --exclude node_modules --exclude dist --exclude test "$SRC/" "$APP/"
cd "$APP"
npm ci --no-audit --no-fund            # installs dev deps too (needed for tsc/prisma); postinstall runs prisma generate
npm run build
set -a; source "$ENVF"; set +a
npx prisma migrate deploy
chown -R root:root "$APP"

echo "==> systemd service"
cat > /etc/systemd/system/health-diary.service <<UNIT
[Unit]
Description=Health Diary API
After=network.target postgresql.service

[Service]
User=hd
Group=hd
WorkingDirectory=$APP
EnvironmentFile=$ENVF
ExecStart=/usr/bin/node dist/server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable health-diary
systemctl restart health-diary

if [[ $USE_NGINX -eq 1 ]]; then
  echo "==> nginx vhost + Let's Encrypt for $DOMAIN (your other sites are not touched)"
  systemctl disable --now caddy 2>/dev/null || true
  apt-get install -y certbot python3-certbot-nginx
  # Debian-style (sites-available/sites-enabled) or conf.d-style layout, whichever this nginx actually loads.
  if [[ -d /etc/nginx/sites-enabled ]] && nginx -T 2>/dev/null | grep -q 'sites-enabled'; then
    NGX_CONF=/etc/nginx/sites-available/health-diary
    NGX_LINK=/etc/nginx/sites-enabled/health-diary
  else
    NGX_CONF=/etc/nginx/conf.d/health-diary.conf
    NGX_LINK=""
  fi
  mkdir -p "$(dirname "$NGX_CONF")"
  cat > "$NGX_CONF" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 2m;
    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  [[ -z "$NGX_LINK" ]] || ln -sf "$NGX_CONF" "$NGX_LINK"
  echo "nginx config written to $NGX_CONF"
  nginx -t
  systemctl reload nginx
  CB=(--nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect)
  if [[ -n "${CERTBOT_EMAIL:-}" ]]; then CB+=(-m "$CERTBOT_EMAIL"); else CB+=(--register-unsafely-without-email); fi
  if ! certbot "${CB[@]}"; then
    echo "!! HTTPS certificate was NOT issued (see message above). The API is running; plain HTTP works at http://$DOMAIN/health."
    echo "!! Fix DNS/domain and re-run this script, or run: sudo certbot --nginx -d $DOMAIN"
  fi
else
  echo "==> Caddy (HTTPS for $DOMAIN)"
  cat > /etc/caddy/health-diary.caddy <<CADDY
$DOMAIN {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8787
}
CADDY
  touch /etc/caddy/Caddyfile
  grep -qF "import /etc/caddy/health-diary.caddy" /etc/caddy/Caddyfile || echo "import /etc/caddy/health-diary.caddy" >> /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy
fi

echo "==> daily backup (03:30, keeps 14 days) -> $BACKUPS"
mkdir -p "$BACKUPS"; chown postgres:postgres "$BACKUPS"; chmod 700 "$BACKUPS"
cat > /usr/local/bin/hd-backup <<'BAK'
#!/usr/bin/env bash
set -euo pipefail
D=/var/backups/health-diary
pg_dump -Fc healthdiary > "$D/healthdiary-$(date +%F).dump"
find "$D" -type f -mtime +14 -delete
BAK
chmod +x /usr/local/bin/hd-backup
echo "30 3 * * * postgres /usr/local/bin/hd-backup" > /etc/cron.d/health-diary-backup

if [[ "$FIREWALL" == "--firewall" ]]; then
  echo "==> firewall: allow SSH(22), 80, 443 only"
  apt-get install -y ufw
  ufw allow OpenSSH; ufw allow 80/tcp; ufw allow 443/tcp
  ufw --force enable
fi

sleep 3
echo
systemctl is-active health-diary && echo "API service: running"
echo "Local check : $(curl -fsS http://127.0.0.1:8787/health || echo FAILED)"
echo "Public check: curl https://$DOMAIN/health   (the HTTPS certificate can take ~30s the first time)"
echo
echo "Admin key (to verify pharmacies):  sudo grep ADMIN_KEY $ENVF"
echo "Backups: $BACKUPS  — copy them OFF this server regularly (scp/rsync to your PC)."
