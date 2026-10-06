#!/usr/bin/env bash
# Arbeitstaschen-Server auf einem eigenen Linux-Server installieren (Ubuntu 22.04/24.04 oder Debian 12) – ein Befehl:
#
#   curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/taschen/server/install.sh | sudo bash
#
# Läuft auch neben anderen Diensten auf demselben Server: eigener Dienst, eigener Port 8082, eigene Adresse.
# Richtet ein: Node.js 22, Arbeitstaschen als abgeschotteter Dienst (Sync zwischen iPhone, iPad und Mac, Erinnerungen per
# Web Push, optional der KI-Projektmanager mit Claude), Caddy mit automatischem HTTPS, Firewall, fail2ban, automatische
# Sicherheitsupdates, tägliche Backups und den Befehl „taschen-update“.
# Ohne eigene Domain gibt es eine kostenlose HTTPS-Adresse der Form taschen.1-2-3-4.sslip.io.
#
# Ohne Rückfragen (z. B. per Skript):  TASCHEN_DOMAIN=… ANTHROPIC_API_KEY=… ALLOWED_ORIGINS=… VAPID_SUBJECT=… bash install.sh
set -euo pipefail

REPO="https://github.com/georgleomaser-bit/website-test-demo-1.git"
APP=/opt/taschen
DATA=/var/lib/taschen
ENVF=/etc/taschen.env
PORT=8082
DEFAULT_ORIGINS="https://georgleomaser-bit.github.io"

say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
warn() { printf '  \033[1;33m⚠️  %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }
ask() {
  local v=""
  if [ -r /dev/tty ]; then { read -r -p "$1" v </dev/tty; } 2>/dev/null || true; fi
  printf '%s' "$v"
}
# Wert in /etc/taschen.env setzen (ersetzt einen vorhandenen)
setenv() {
  touch "$ENVF"
  chmod 600 "$ENVF"
  sed -i "/^$1=/d" "$ENVF"
  printf '%s=%s\n' "$1" "$2" >>"$ENVF"
}
# Vorhandenen Wert lesen (leer, wenn nicht gesetzt)
getenv() { [ -f "$ENVF" ] && sed -n "s/^$1=//p" "$ENVF" | tail -n 1 || true; }

[ "$(id -u)" = 0 ] || die "Bitte mit sudo bzw. als root ausführen."
command -v apt-get >/dev/null || die "Dieses Skript ist für Ubuntu/Debian gedacht."
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl >/dev/null; }

IP=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
[ -n "$IP" ] || die "Konnte die öffentliche IP-Adresse dieses Servers nicht ermitteln."
FREE_HOST="taschen.$(printf '%s' "$IP" | tr . -).sslip.io"
OLD_DOMAIN=$(getenv ALLOWED_HOSTS)

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   👜 Arbeitstaschen – Server-Installation     ║"
echo "  ╚══════════════════════════════════════════════╝"
echo "  Sync zwischen deinen Geräten, Erinnerungen per Push und dein KI-Projektmanager."
echo ""
DOMAIN=${TASCHEN_DOMAIN:-$(ask "  Eigene Domain (z. B. taschen.meine-firma.de) – Enter für ${OLD_DOMAIN:-die kostenlose Adresse $FREE_HOST}: ")}
DOMAIN=${DOMAIN:-${OLD_DOMAIN:-$FREE_HOST}}
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*##; s#:.*##')
printf '%s' "$DOMAIN" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' || die "„$DOMAIN“ ist keine gültige Domain."

OLD_KEY=$(getenv ANTHROPIC_API_KEY)
KEEP=$([ -n "$OLD_KEY" ] && echo "behält den bisherigen" || echo "überspringt")
KEY=${ANTHROPIC_API_KEY:-$(ask "  Anthropic-API-Schlüssel (sk-ant-…) für den KI-Projektmanager – optional, Enter $KEEP: ")}
KEY=${KEY:-$OLD_KEY}
KEY=$(printf '%s' "$KEY" | tr -d '[:space:]')
case "$KEY" in "" | sk-ant-*) ;; *) warn "Das sieht nicht nach einem Anthropic-Schlüssel aus (sk-ant-…) – KI bleibt aus."; KEY="" ;; esac

ORIGINS=${ALLOWED_ORIGINS:-${TASCHEN_ORIGINS:-$(getenv ALLOWED_ORIGINS)}}
ORIGINS=${ORIGINS:-$DEFAULT_ORIGINS}
SUBJECT=${VAPID_SUBJECT:-$(getenv VAPID_SUBJECT)}
DEFAULT_SUBJECT="https://$DOMAIN" # Kontakt für die Push-Dienste: die eigene Adresse
SUBJECT=${SUBJECT:-$DEFAULT_SUBJECT}
case "$SUBJECT" in mailto:*@* | https://*) ;; *) warn "VAPID_SUBJECT muss mit mailto: oder https: beginnen – nehme $DEFAULT_SUBJECT."; SUBJECT=$DEFAULT_SUBJECT ;; esac

if [ "$DOMAIN" != "$FREE_HOST" ]; then
  RESOLVED=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
  [ "$RESOLVED" = "$IP" ] || warn "$DOMAIN zeigt noch nicht auf diesen Server ($IP) – A-Eintrag „$DOMAIN → $IP“ beim Domain-Anbieter anlegen."
fi

say "Pakete installieren (dauert 1–3 Minuten)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ca-certificates gnupg openssl ufw fail2ban unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https >/dev/null
if ! command -v node >/dev/null || [ "$(node -v | sed 's/^v//; s/\..*//')" -lt 22 ]; then
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

say "Arbeitstaschen herunterladen"
id taschen >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin taschen
if [ -d "$APP/.git" ]; then
  git -c safe.directory="$APP" -C "$APP" pull -q --ff-only
else
  git clone -q --depth 1 "$REPO" "$APP"
fi
# Nur für die KI nötig (@anthropic-ai/sdk) – Sync und Push laufen auch ohne
(cd "$APP" && npm install --omit=dev --no-audit --no-fund --silent) || warn "npm install fehlgeschlagen – Sync und Push laufen trotzdem, die KI erst nach einem erfolgreichen „taschen-update“."
mkdir -p "$DATA"
chown -R taschen:taschen "$APP" "$DATA"
chmod 700 "$DATA"

say "Einstellungen ($ENVF)"
setenv PORT "$PORT"
setenv HOST 127.0.0.1
setenv DATA_DIR "$DATA"
setenv TRUST_PROXY 1
setenv PROXY_IP_HEADER x-forwarded-for
setenv ALLOWED_HOSTS "$DOMAIN"
setenv ALLOWED_ORIGINS "$ORIGINS"
setenv VAPID_SUBJECT "$SUBJECT"
[ -n "$KEY" ] && setenv ANTHROPIC_API_KEY "$KEY"
[ -n "$(getenv TASCHEN_AI_DAILY)" ] || setenv TASCHEN_AI_DAILY 100
chown root:root "$ENVF"
chmod 600 "$ENVF"

say "Dienst einrichten"
cat >/etc/systemd/system/taschen.service <<EOF
[Unit]
Description=Arbeitstaschen – Sync, Erinnerungen und KI-Projektmanager
After=network-online.target
Wants=network-online.target

[Service]
User=taschen
Group=taschen
EnvironmentFile=$ENVF
WorkingDirectory=$APP
ExecStart=$(command -v node) taschen/server/taschen-server.mjs
Restart=always
RestartSec=3
TimeoutStopSec=15
LimitNOFILE=8192
MemoryMax=768M
NoNewPrivileges=true
UMask=0077
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectProc=invisible
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
systemctl enable -q taschen
systemctl restart taschen

say "HTTPS für $DOMAIN einrichten"
mkdir -p /etc/caddy/sites
# Alte Einzel-Konfiguration von AKYTEX übernehmen, falls vorhanden (NOVA macht es genauso)
if [ -f /etc/caddy/Caddyfile ] && ! grep -q "import /etc/caddy/sites" /etc/caddy/Caddyfile; then
  grep -q "reverse_proxy 127.0.0.1:8080" /etc/caddy/Caddyfile && cp /etc/caddy/Caddyfile /etc/caddy/sites/akytex.caddy
fi
printf 'import /etc/caddy/sites/*.caddy\n' >/etc/caddy/Caddyfile
cat >/etc/caddy/sites/taschen.caddy <<EOF
$DOMAIN {
	encode zstd gzip
	header -Server
	request_body {
		max_size 16MB
	}
	reverse_proxy 127.0.0.1:$PORT
}
EOF
if ! caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
  warn "Die Caddy-Konfiguration ist ungültig – prüfe: caddy validate --config /etc/caddy/Caddyfile"
fi
systemctl enable -q caddy
systemctl reload caddy 2>/dev/null || systemctl restart caddy

say "Firewall, Schutz und Backups"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
systemctl enable -q --now fail2ban 2>/dev/null || true
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades
mkdir -p /var/backups/taschen
chmod 700 /var/backups/taschen
cat >/etc/cron.daily/taschen-backup <<'EOF'
#!/bin/sh
# Tägliche Sicherung der Arbeitstaschen-Daten (Sync-Stände sind verschlüsselt, dazu Push-Abos und Schlüssel) – 14 Tage aufbewahren
umask 077
tar -czf "/var/backups/taschen/taschen-$(date +%F).tgz" -C /var/lib taschen 2>/dev/null
find /var/backups/taschen -name 'taschen-*.tgz' -mtime +14 -delete
EOF
chmod +x /etc/cron.daily/taschen-backup
cat >/usr/local/bin/taschen-update <<EOF
#!/bin/sh
# Arbeitstaschen auf den neuesten Stand bringen
set -e
git -c safe.directory=$APP -C $APP pull -q --ff-only
cd $APP && npm install --omit=dev --no-audit --no-fund --silent
chown -R taschen:taschen $APP
systemctl restart taschen
sleep 2
if curl -fsS --max-time 5 http://127.0.0.1:$PORT/api/health >/dev/null; then echo "✅ Arbeitstaschen ist aktuell."; else echo "⚠️  Der Dienst antwortet nicht – prüfe: journalctl -u taschen -n 50"; fi
EOF
chmod +x /usr/local/bin/taschen-update

STATUS=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  STATUS=$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/api/health" 2>/dev/null || true)
  [ -n "$STATUS" ] && break
  sleep 1
done
echo ""
echo "  ════════════════════════════════════════════════════════════"
if [ -n "$STATUS" ]; then echo "  ✅ Arbeitstaschen läuft!"; else echo "  ⚠️  Arbeitstaschen antwortet noch nicht – prüfe: journalctl -u taschen -n 50"; fi
echo ""
echo "     Adresse:     https://$DOMAIN"
echo "     Sync:        an (Ende-zu-Ende-verschlüsselt – der Server sieht nie deine Inhalte)"
echo "     Erinnerungen: $(printf '%s' "$STATUS" | grep -q '"push":true' && echo 'Web Push bereit' || echo 'noch nicht bereit')"
MODEL_SHOWN=$(getenv TASCHEN_MODEL)
echo "     KI-PM:       $(printf '%s' "$STATUS" | grep -q '"ai":true' && echo "Claude aktiv (${MODEL_SHOWN:-claude-opus-5-5}, $(getenv TASCHEN_AI_DAILY) Fragen/Tag)" || echo 'aus – Skript erneut starten und Anthropic-Schlüssel eingeben')"
echo "     Freigegeben: $ORIGINS"
echo ""
echo "     So verbindest du deine Geräte:"
echo "       1. Öffne https://$DOMAIN in Safari und füge die App zum Home-Bildschirm"
echo "          bzw. zum Dock hinzu – oder trag die Adresse in der App unter"
echo "          Einstellungen → Sync als Server ein."
echo "       2. Auf jedem weiteren Gerät denselben Sync-Code eingeben – fertig."
echo ""
echo "     Aktualisieren: taschen-update"
echo "     Logs ansehen:  journalctl -u taschen -f"
echo "     Einstellungen: $ENVF (danach: systemctl restart taschen)"
echo "  ════════════════════════════════════════════════════════════"
echo "  Das HTTPS-Zertifikat holt Caddy automatisch – die Adresse ist meist nach 1 Minute erreichbar."
