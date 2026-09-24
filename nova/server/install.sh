#!/usr/bin/env bash
# NOVA auf einem eigenen Linux-Server installieren (Ubuntu 22.04/24.04 oder Debian 12) – ein Befehl:
#
#   curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/nova/server/install.sh | sudo bash
#
# Läuft neben AKYTEX auf demselben Server (eigener Dienst, eigener Port 8081, eigene Adresse).
# Richtet ein: Node.js 22, NOVA als abgeschotteter Dienst, Caddy mit automatischem HTTPS, Firewall,
# fail2ban, automatische Sicherheitsupdates, tägliche Backups und den Befehl „nova-update“.
# Ohne eigene Domain gibt es eine kostenlose HTTPS-Adresse der Form nova.1-2-3-4.sslip.io.
set -euo pipefail

REPO="https://github.com/georgleomaser-bit/website-test-demo-1.git"
APP=/opt/nova
DATA=/var/lib/nova
ENVF=/etc/nova.env

say() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }
ask() {
  local v=""
  if [ -r /dev/tty ]; then { read -r -p "$1" v </dev/tty; } 2>/dev/null || true; fi
  printf '%s' "$v"
}
setenv() {
  touch "$ENVF"
  sed -i "/^$1=/d" "$ENVF"
  printf '%s=%s\n' "$1" "$2" >>"$ENVF"
}

[ "$(id -u)" = 0 ] || die "Bitte mit sudo bzw. als root ausführen."
command -v apt-get >/dev/null || die "Dieses Skript ist für Ubuntu/Debian gedacht."

IP=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
FREE_HOST="nova.$(printf '%s' "$IP" | tr . -).sslip.io"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   NOVA – Server-Installation             ║"
echo "  ╚══════════════════════════════════════════╝"
DOMAIN=${NOVA_DOMAIN:-$(ask "  Eigene Domain für NOVA (z. B. nova-app.de) – Enter für die kostenlose Adresse $FREE_HOST: ")}
DOMAIN=${DOMAIN:-$FREE_HOST}
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*##')
KEY=${ANTHROPIC_API_KEY:-$(ask "  Anthropic-API-Schlüssel (sk-ant-…) – ohne ihn laufen nur Wetter, Timer & Co.: ")}
STRIPE=${STRIPE_SECRET_KEY:-$(ask "  Eingeschränkter Stripe-Schlüssel rk_live_… (optional – Enter zum Überspringen): ")}
case "$STRIPE" in "" | rk_*) ;; *) echo "  ⚠️  Bitte nur einen eingeschränkten Schlüssel (rk_…) mit Leserechten verwenden."; STRIPE="" ;; esac

if [ "$DOMAIN" != "$FREE_HOST" ]; then
  RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
  [ "$RESOLVED" = "$IP" ] || echo "  ⚠️  $DOMAIN zeigt noch nicht auf diesen Server ($IP) – A-Eintrag „@ → $IP“ beim Domain-Anbieter anlegen."
fi

say "Pakete installieren (dauert 1–3 Minuten)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates gnupg openssl ufw fail2ban unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https >/dev/null
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

say "NOVA herunterladen"
id nova >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin nova
if [ -d "$APP/.git" ]; then
  git -c safe.directory="$APP" -C "$APP" pull -q --ff-only
else
  git clone -q --depth 1 "$REPO" "$APP"
fi
(cd "$APP" && npm install --omit=dev --no-audit --no-fund --silent)
mkdir -p "$DATA"
chown -R nova:nova "$APP" "$DATA"
chmod 700 "$DATA"

say "Einstellungen"
setenv PORT 8081
setenv HOST 127.0.0.1
setenv DATA_DIR "$DATA"
setenv TRUST_PROXY 1
setenv PROXY_IP_HEADER x-forwarded-for
setenv ALLOWED_HOSTS "$DOMAIN"
[ -n "$KEY" ] && setenv ANTHROPIC_API_KEY "$KEY"
[ -n "$STRIPE" ] && setenv STRIPE_SECRET_KEY "$STRIPE"
chmod 600 "$ENVF"

say "Dienst einrichten"
cat >/etc/systemd/system/nova.service <<EOF
[Unit]
Description=NOVA KI-Assistent
After=network-online.target
Wants=network-online.target

[Service]
User=nova
Group=nova
EnvironmentFile=$ENVF
WorkingDirectory=$APP
ExecStart=$(command -v node) nova/server/nova-server.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
UMask=0077
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
ReadWritePaths=$DATA

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q nova
systemctl restart nova

say "HTTPS für $DOMAIN einrichten"
mkdir -p /etc/caddy/sites
# Alte Einzel-Konfiguration von AKYTEX übernehmen, falls vorhanden
if [ -f /etc/caddy/Caddyfile ] && ! grep -q "import /etc/caddy/sites" /etc/caddy/Caddyfile; then
  grep -q "reverse_proxy 127.0.0.1:8080" /etc/caddy/Caddyfile && cp /etc/caddy/Caddyfile /etc/caddy/sites/akytex.caddy
fi
printf 'import /etc/caddy/sites/*.caddy\n' >/etc/caddy/Caddyfile
cat >/etc/caddy/sites/nova.caddy <<EOF
$DOMAIN {
	encode zstd gzip
	header -Server
	request_body {
		max_size 16MB
	}
	reverse_proxy 127.0.0.1:8081
}
EOF
systemctl enable -q caddy
systemctl restart caddy

say "Firewall, Schutz und Backups"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
systemctl enable -q --now fail2ban 2>/dev/null || true
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades
mkdir -p /var/backups/nova
cat >/etc/cron.daily/nova-backup <<'EOF'
#!/bin/sh
# Tägliche Sicherung der NOVA-Daten (Konten, Käufe) – 14 Tage aufbewahren
tar -czf "/var/backups/nova/nova-$(date +%F).tgz" -C /var/lib nova 2>/dev/null
find /var/backups/nova -name 'nova-*.tgz' -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/nova-backup
cat >/usr/local/bin/nova-update <<EOF
#!/bin/sh
# NOVA auf den neuesten Stand bringen
set -e
git -c safe.directory=$APP -C $APP pull -q --ff-only
cd $APP && npm install --omit=dev --no-audit --no-fund --silent
chown -R nova:nova $APP
systemctl restart nova
echo "✅ NOVA ist aktuell."
EOF
chmod +x /usr/local/bin/nova-update

sleep 2
STATUS=$(curl -fsS --max-time 5 http://127.0.0.1:8081/api/health || echo "")
echo ""
echo "  ════════════════════════════════════════════════════════"
if [ -n "$STATUS" ]; then echo "  ✅ NOVA läuft!"; else echo "  ⚠️  NOVA antwortet noch nicht – prüfe: journalctl -u nova -n 50"; fi
echo ""
echo "     Adresse:  https://$DOMAIN"
echo "     KI:       $(printf '%s' "$STATUS" | grep -q '"ai":true' && echo 'Claude aktiv' || echo 'aus – Skript erneut starten und Anthropic-Schlüssel eingeben')"
echo "     Käufe:    $(printf '%s' "$STATUS" | grep -q '"billing":true' && echo 'werden bei Stripe geprüft' || echo 'noch ohne Stripe – alle haben Free (5 KI-Fragen/Tag). Zum Testen: NOVA_OPEN_PLAN=pro in /etc/nova.env, dann systemctl restart nova')"
echo ""
echo "     Aktualisieren: nova-update"
echo "     Logs ansehen:  journalctl -u nova -f"
echo "  ════════════════════════════════════════════════════════"
echo "  Das HTTPS-Zertifikat holt Caddy automatisch – die Adresse ist meist nach 1 Minute erreichbar."
