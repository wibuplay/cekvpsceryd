#!/bin/bash
# Cerydra Multi-VPS agent
#
# Pasang : bash install.sh <URL-BOT> <TOKEN>
# Copot  : bash install.sh uninstall
#
# URL-BOT dan TOKEN diambil dari bot lewat command /cekserver (chat pribadi).
# Jangan pernah commit token ke repo ini.

DIR=/opt/cerydra-vps

if [ "$(id -u)" != "0" ]; then
  echo "❌ Jalankan sebagai root (sudo -i dulu)."
  exit 1
fi

if [ "${1:-}" = "uninstall" ]; then
  systemctl disable --now cerydra-vps.timer >/dev/null 2>&1
  rm -f /etc/systemd/system/cerydra-vps.service /etc/systemd/system/cerydra-vps.timer
  systemctl daemon-reload
  rm -rf "$DIR"
  echo "✅ Agent dicopot dari VPS ini."
  echo "   (Hapus juga dari list bot pakai /cekserver hapus $(hostname))"
  exit 0
fi

BASE="${1:-}"
TOKEN="${2:-}"

if [ -z "$BASE" ] || [ -z "$TOKEN" ]; then
  echo "Cara pakai : bash install.sh <URL-BOT> <TOKEN>"
  echo "Contoh     : bash install.sh https://bot.domainmu.com abc123def456"
  echo "Command lengkap (sudah ada token) ambil dari bot: /cekserver"
  exit 1
fi

BASE="${BASE%/}"

if ! [[ "$BASE" =~ ^https?://[A-Za-z0-9.:-]+$ ]]; then
  echo "❌ URL bot tidak valid: $BASE"
  exit 1
fi
if ! [[ "$TOKEN" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "❌ Token tidak valid (harus huruf/angka saja)."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq curl
fi

mkdir -p "$DIR"

printf 'URL="%s/vps/report"\nTOKEN="%s"\n' "$BASE" "$TOKEN" > "$DIR/agent.conf"
chmod 600 "$DIR/agent.conf"

cat > "$DIR/report.sh" <<'REPORT'
#!/bin/bash
. /opt/cerydra-vps/agent.conf
HOST=$(hostname)
ID=$(cat /etc/machine-id 2>/dev/null || echo "$HOST")
UP=$(cut -d. -f1 /proc/uptime)
OS=$(. /etc/os-release 2>/dev/null; echo "${NAME:-Linux} ${VERSION_ID:-}")
CPU=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
RAMT=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)
RAMA=$(awk '/^MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)
RAMU=$((RAMT - RAMA))
read -r DT DU < <(df -Pm / | awk 'NR==2 {print $2, $3}')
CODE=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -X POST "$URL" \
  --data-urlencode "token=$TOKEN" \
  --data-urlencode "host=$HOST" \
  --data-urlencode "id=$ID" \
  --data-urlencode "up=$UP" \
  --data-urlencode "os=$OS" \
  --data-urlencode "cpu=$CPU" \
  --data-urlencode "ramt=$RAMT" \
  --data-urlencode "ramu=$RAMU" \
  --data-urlencode "dt=$DT" \
  --data-urlencode "du=$DU" \
  --data-urlencode "fresh=${1:-0}")
echo "$CODE"
# 410 = VPS ini sudah dihapus dari bot -> agent uninstall dirinya sendiri
if [ "$CODE" = "410" ]; then
  systemctl disable --now cerydra-vps.timer >/dev/null 2>&1
  rm -f /etc/systemd/system/cerydra-vps.service /etc/systemd/system/cerydra-vps.timer
  systemctl daemon-reload
  rm -rf /opt/cerydra-vps
fi
REPORT
chmod +x "$DIR/report.sh"

cat > /etc/systemd/system/cerydra-vps.service <<'UNIT'
[Unit]
Description=Cerydra VPS reporter

[Service]
Type=oneshot
ExecStart=/opt/cerydra-vps/report.sh
UNIT

cat > /etc/systemd/system/cerydra-vps.timer <<'UNIT'
[Unit]
Description=Cerydra VPS reporter timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now cerydra-vps.timer >/dev/null 2>&1

CODE=$("$DIR/report.sh" 1)
case "$CODE" in
  200) echo "✅ Berhasil! VPS '$(hostname)' sudah terdaftar di bot. Cek dengan /statsvps" ;;
  401) echo "❌ Token ditolak bot. Ambil ulang command install lewat /cekserver" ;;
  000) echo "❌ Tidak bisa konek ke $BASE dari VPS ini. Cek domain/port bot." ;;
  *)   echo "⚠️ Bot membalas HTTP $CODE" ;;
esac
