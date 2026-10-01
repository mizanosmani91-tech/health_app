#!/usr/bin/env bash
# Installs the Health Diary API on a fresh Ubuntu VPS: Node, the app (systemd), Caddy (automatic HTTPS), daily backups.
# Safe to re-run (it updates the code and keeps your existing secrets/data).
#
#   git clone <repo> && cd health_app
#   sudo bash server/deploy/setup.sh <domain> <google-web-client-id> [--firewall]
#
# <domain>  e.g. vps-2976817d.vps.ovh.ca  (must already point at this server; port 80/443 reachable)
set -euo pipefail

DOMAIN="${1:-}"; CLIENT_ID="${2:-}"; FIREWALL="${3:-}"
[[ -n "$DOMAIN" && -n "$CLIENT_ID" ]] || { echo "usage: sudo bash $0 <domain> <google-web-client-id> [--firewall]"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/health-diary
DATA=/var/lib/health-diary
ENVF=/etc/health-diary.env
export DEBIAN_FRONTEND=noninteractive

echo "==> packages"
apt-get update -y
apt-get install -y curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https sqlite3 rsync openssl

need_node=1
if command -v node >/dev/null; then
  node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a==22&&b>=13)?0:1)' && need_node=0 || true
fi
if [[ $need_node -eq 1 ]]; then
  echo "==> installing Node 22"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

if ! command -v caddy >/dev/null; then
  echo "==> installing Caddy"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y
  apt-get install -y caddy
fi

echo "==> app user, code, data"
id -u hd >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin hd
mkdir -p "$APP" "$DATA/backups"
rsync -a --delete --exclude node_modules --exclude data --exclude test "$SRC/" "$APP/"
(cd "$APP" && npm ci --omit=dev --no-audit --no-fund)
chown -R root:root "$APP"
chown -R hd:hd "$DATA"
chmod 700 "$DATA"

echo "==> config ($ENVF)"
if [[ ! -f "$ENVF" ]]; then
  umask 077
  cat > "$ENVF" <<ENV
PORT=8787
DATA_DIR=$DATA
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_KEY=$(openssl rand -hex 24)
GOOGLE_CLIENT_IDS=$CLIENT_ID
ENV
else
  # keep secrets, but let the client id be updated on re-run
  sed -i "s|^GOOGLE_CLIENT_IDS=.*|GOOGLE_CLIENT_IDS=$CLIENT_ID|" "$ENVF"
fi
chown root:hd "$ENVF"; chmod 640 "$ENVF"

echo "==> systemd service"
cat > /etc/systemd/system/health-diary.service <<UNIT
[Unit]
Description=Health Diary API
After=network.target

[Service]
User=hd
Group=hd
WorkingDirectory=$APP
EnvironmentFile=$ENVF
ExecStart=/usr/bin/node --no-warnings src/server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$DATA

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now health-diary
systemctl restart health-diary

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

echo "==> daily backup (03:30, keeps 14 days) -> $DATA/backups"
cat > /usr/local/bin/hd-backup <<'BAK'
#!/usr/bin/env bash
set -euo pipefail
D=/var/lib/health-diary; T=$(date +%F)
sqlite3 "$D/app.db" ".backup '$D/backups/app-$T.db'"
tar -C "$D" -czf "$D/backups/licenses-$T.tgz" licenses 2>/dev/null || true
find "$D/backups" -type f -mtime +14 -delete
BAK
chmod +x /usr/local/bin/hd-backup
echo "30 3 * * * hd /usr/local/bin/hd-backup" > /etc/cron.d/health-diary-backup

if [[ "$FIREWALL" == "--firewall" ]]; then
  echo "==> firewall: allow SSH(22), 80, 443 only"
  apt-get install -y ufw
  ufw allow OpenSSH; ufw allow 80/tcp; ufw allow 443/tcp
  ufw --force enable
fi

sleep 2
echo
systemctl is-active health-diary && echo "API service: running"
echo "Local check : $(curl -fsS http://127.0.0.1:8787/health || echo FAILED)"
echo "Public check: curl https://$DOMAIN/health   (HTTPS certificate can take ~30s the first time)"
echo
echo "Admin key (to verify pharmacies):  sudo grep ADMIN_KEY $ENVF"
echo "IMPORTANT: copy $DATA/backups off this server regularly (e.g. rsync/scp to your PC)."
