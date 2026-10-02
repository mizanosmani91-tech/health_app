#!/usr/bin/env bash
# One-command update of the Health Diary API on the VPS (after the first setup).
#   sudo bash /opt/health-diary-src/server/deploy/update.sh        # (or run it from any checkout of the repo)
# Keeps a persistent git checkout in /opt/health-diary-src, builds in /opt/health-diary, applies new
# migrations, restarts the service and checks /health. Secrets (/etc/health-diary.env) and data are untouched.
set -euo pipefail
umask 022   # root's umask may be strict; the service user (hd) must be able to read dist/ and node_modules/
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

REPO="${REPO:-https://github.com/mizanosmani91-tech/health_app}"
BRANCH="${BRANCH:-claude/family-health-tracker-oa9nmf}"
SRC=/opt/health-diary-src
APP=/opt/health-diary
ENVF=/etc/health-diary.env

echo "==> fetching $BRANCH"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC" checkout -q -B "$BRANCH" FETCH_HEAD
else
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$SRC"
fi
echo "now at: $(git -C "$SRC" log -1 --format='%h %s')"

echo "==> syncing server/ -> $APP"
rsync -a --delete --exclude node_modules --exclude dist --exclude test "$SRC/server/" "$APP/"
cd "$APP"
npm ci --no-audit --no-fund
npm run build
[[ -f dist/server.js ]] || { echo "!! build failed"; exit 1; }
set -a; source "$ENVF"; set +a
npx prisma migrate deploy
chown -R root:root "$APP"
chmod -R go+rX "$APP"   # readable by the unprivileged service user

echo "==> restarting"
systemctl restart health-diary
sleep 3
systemctl is-active health-diary
echo "health: $(curl -fsS http://127.0.0.1:8787/health || echo FAILED)"
