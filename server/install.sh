#!/usr/bin/env bash
# AKYTEX auf einem eigenen Linux-Server installieren (Ubuntu 22.04/24.04 oder Debian 12) – ein Befehl, alles automatisch:
#
#   curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/server/install.sh | sudo bash
#
# Richtet ein: Node.js 22, AKYTEX als Dienst (startet nach Absturz/Neustart von selbst), Caddy mit automatischem HTTPS,
# Firewall, tägliche Backups und den Befehl „akytex-update“. Ohne eigene Domain gibt es eine kostenlose
# HTTPS-Adresse der Form 1-2-3-4.sslip.io. Mehrfach ausführen ist ungefährlich (z. B. um die Domain zu ändern).
set -euo pipefail

REPO="https://github.com/georgleomaser-bit/website-test-demo-1.git"
APP=/opt/akytex
DATA=/var/lib/akytex
ENVF=/etc/akytex.env

say() { printf '\n\033[1;33m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }
# Eingaben kommen bei „curl … | bash“ vom Terminal, nicht aus der Pipe
ask() {
  local v=""
  if [ -r /dev/tty ]; then { read -r -p "$1" v </dev/tty; } 2>/dev/null || true; fi
  printf '%s' "$v"
}
setenv() { # Schlüssel=Wert in /etc/akytex.env setzen oder ersetzen
  touch "$ENVF"
  sed -i "/^$1=/d" "$ENVF"
  printf '%s=%s\n' "$1" "$2" >>"$ENVF"
}

[ "$(id -u)" = 0 ] || die "Bitte mit sudo bzw. als root ausführen."
command -v apt-get >/dev/null || die "Dieses Skript ist für Ubuntu/Debian gedacht."

IP=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
FREE_HOST="$(printf '%s' "$IP" | tr . -).sslip.io"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   AKYTEX – Server-Installation           ║"
echo "  ╚══════════════════════════════════════════╝"
DOMAIN=${AKYTEX_DOMAIN:-$(ask "  Eigene Domain (z. B. akytex.org) – Enter für die kostenlose Adresse $FREE_HOST: ")}
DOMAIN=${DOMAIN:-$FREE_HOST}
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*##')
KEY=${ANTHROPIC_API_KEY:-$(ask "  Anthropic-API-Schlüssel für das Sprachmodell (optional – Enter zum Überspringen): ")}

if [ "$DOMAIN" != "$FREE_HOST" ]; then
  RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
  if [ "$RESOLVED" != "$IP" ]; then
    echo ""
    echo "  ⚠️  $DOMAIN zeigt noch nicht auf diesen Server ($IP)."
    echo "     Lege beim Domain-Anbieter einen A-Eintrag „@ → $IP“ an. HTTPS klappt, sobald er aktiv ist."
  fi
fi

say "Pakete installieren (dauert 1–3 Minuten)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates gnupg openssl ufw debian-keyring debian-archive-keyring apt-transport-https >/dev/null

if ! command -v node >/dev/null || [ "$(node -v | sed 's/^v//; s/\..*//')" -lt 20 ]; then
  say "Node.js 22 installieren"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi

if ! command -v caddy >/dev/null; then
  say "Caddy (automatisches HTTPS) installieren"
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt >/etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy >/dev/null
fi

say "AKYTEX herunterladen"
id akytex >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin akytex
if [ -d "$APP/.git" ]; then
  git -c safe.directory="$APP" -C "$APP" pull -q --ff-only
else
  git clone -q --depth 1 "$REPO" "$APP"
fi
(cd "$APP" && npm install --omit=dev --no-audit --no-fund --silent)
mkdir -p "$DATA"
chown -R akytex:akytex "$APP" "$DATA"

say "Einstellungen"
grep -q '^ADMIN_TOKEN=' "$ENVF" 2>/dev/null || setenv ADMIN_TOKEN "$(openssl rand -hex 24)"
setenv PORT 8080
setenv DATA_DIR "$DATA"
setenv TRUST_PROXY 1
setenv PROXY_IP_HEADER x-forwarded-for
setenv ALLOWED_HOSTS "$DOMAIN"
[ -n "$KEY" ] && setenv ANTHROPIC_API_KEY "$KEY"
chmod 600 "$ENVF"

say "Dienst einrichten"
cat >/etc/systemd/system/akytex.service <<EOF
[Unit]
Description=AKYTEX
After=network-online.target
Wants=network-online.target

[Service]
User=akytex
Group=akytex
EnvironmentFile=$ENVF
WorkingDirectory=$APP
ExecStart=$(command -v node) server/akytex-server.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$DATA

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q akytex
systemctl restart akytex

say "HTTPS für $DOMAIN einrichten"
mkdir -p /etc/caddy
cat >/etc/caddy/Caddyfile <<EOF
$DOMAIN {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080
}
EOF
systemctl enable -q caddy
systemctl restart caddy

say "Firewall und Backups"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
mkdir -p /var/backups/akytex
cat >/etc/cron.daily/akytex-backup <<'EOF'
#!/bin/sh
# Tägliche Sicherung der AKYTEX-Daten (Nutzer, Clips, Videos) – 14 Tage aufbewahren
tar -czf "/var/backups/akytex/akytex-$(date +%F).tgz" -C /var/lib akytex 2>/dev/null
find /var/backups/akytex -name 'akytex-*.tgz' -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/akytex-backup

cat >/usr/local/bin/akytex-update <<EOF
#!/bin/sh
# AKYTEX auf den neuesten Stand bringen
set -e
git -c safe.directory=$APP -C $APP pull -q --ff-only
cd $APP && npm install --omit=dev --no-audit --no-fund --silent
chown -R akytex:akytex $APP
systemctl restart akytex
echo "✅ AKYTEX ist aktuell."
EOF
chmod +x /usr/local/bin/akytex-update

sleep 2
STATUS=$(curl -fsS --max-time 5 http://127.0.0.1:8080/api/health || echo "")
ADMIN=$(sed -n 's/^ADMIN_TOKEN=//p' "$ENVF")
echo ""
echo "  ════════════════════════════════════════════════════════"
if [ -n "$STATUS" ]; then echo "  ✅ AKYTEX läuft!"; else echo "  ⚠️  Der Dienst antwortet noch nicht – prüfe: journalctl -u akytex -n 50"; fi
echo ""
echo "     Adresse:   https://$DOMAIN"
echo "     KI:        $(printf '%s' "$STATUS" | grep -q '"ai":true' && echo 'Sprachmodell aktiv' || echo 'lokale Engine (Schlüssel in /etc/akytex.env als ANTHROPIC_API_KEY eintragen, dann: systemctl restart akytex)')"
echo "     Moderation: ADMIN_TOKEN=$ADMIN"
echo ""
echo "     Aktualisieren: akytex-update"
echo "     Logs ansehen:  journalctl -u akytex -f"
echo "     Backups:       /var/backups/akytex (täglich, 14 Tage)"
echo "  ════════════════════════════════════════════════════════"
echo "  Das HTTPS-Zertifikat holt Caddy automatisch – die Adresse ist meist nach 1 Minute erreichbar."
