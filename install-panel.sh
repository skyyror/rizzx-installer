#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  RIZZX • Pterodactyl All-in-One Installer  v2.0
#
#  Bisa dipakai MANUAL (tanpa bot Telegram) dan tetap kompatibel dengan bot V8.
#
#    Menu interaktif : sudo bash install-panel.sh
#    Panel           : sudo bash install-panel.sh panel  --fqdn panel.domain.com --ssl
#    Wings           : sudo bash install-panel.sh wings  --panel-url https://panel.domain.com --node-id 1 --token ptla_xxx
#    Panel+Wings+Node: sudo bash install-panel.sh full   --fqdn panel.domain.com --ssl --yes
#    Lainnya         : status | admin | update | --help
#
#  Hasil Panel sama seperti yang diharapkan bot V8:
#    /var/www/pterodactyl • admin "admin" (ID 1) • pteroq + cron • pterodactyl.conf
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

VERSION="2.0.0"
LOG_FILE="/var/log/rizzx-panel-install.log"
PTERO_DIR="/var/www/pterodactyl"
CRED_FILE="/root/rizzx-panel-credentials.txt"
API_KEY_FILE="/root/.rizzx-api-key.tmp"
NODE_STATE_FILE="/root/.rizzx-node-id.tmp"
PHP_VER="8.3"
DB_NAME="panel"
DB_USER="pterodactyl"
ADMIN_USER="admin"          # jangan diganti: bot mencari username "admin"
ADMIN_FIRST="Admin"
ADMIN_LAST="Rizzx"

# ── Konfigurasi (flag / env; nama env bot juga diterima) ─────────────────────
CMD=""
FQDN="${FQDN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-${user_email:-${email:-}}}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-${user_password:-}}"
TIMEZONE="${TIMEZONE:-${timezone:-Asia/Jakarta}}"
ENABLE_SSL="${ENABLE_SSL:-${CONFIGURE_LETSENCRYPT:-ask}}"
PANEL_VERSION="${PANEL_VERSION:-latest}"
MAKE_API_KEY="${MAKE_API_KEY:-false}"
ASSUME_YES="${ASSUME_YES:-false}"
FORCE_OS="${FORCE_OS:-false}"
FORCE_SSL="${FORCE_SSL:-false}"      # true = jangan batalkan SSL walau DNS tampak tidak cocok
REQUIRE_SSL="${REQUIRE_SSL:-false}"  # true = exit != 0 bila SSL gagal terbit (dipakai bot)
NODE_FQDN="${NODE_FQDN:-}"
NODE_NAME="${NODE_NAME:-Node-RIZZX}"
NODE_RAM="${NODE_RAM:-}"
LOC_SHORT="${LOC_SHORT:-ID}"
LOC_LONG="${LOC_LONG:-Indonesia}"
WINGS_PANEL_URL="${WINGS_PANEL_URL:-}"
WINGS_NODE_ID="${WINGS_NODE_ID:-}"
WINGS_TOKEN="${WINGS_TOKEN:-}"

# ── Warna & UI ───────────────────────────────────────────────────────────────
IS_TTY=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then IS_TTY=1; fi
if [[ $IS_TTY == 1 ]]; then
  RST=$'\e[0m'; BLD=$'\e[1m'; DIM=$'\e[2m'
  RED=$'\e[38;5;203m'; GRN=$'\e[38;5;84m'; YEL=$'\e[38;5;221m'
  CYN=$'\e[38;5;81m';  MAG=$'\e[38;5;177m'; GRY=$'\e[38;5;245m'
else
  RST=''; BLD=''; DIM=''; RED=''; GRN=''; YEL=''; CYN=''; MAG=''; GRY=''
fi
CLR=''; if [[ $IS_TTY == 1 ]]; then CLR=$'\r\e[2K'; fi
SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
ERR_SHOWN=0; STEP_NUM=0; STEP_TOTAL=0; SSL_OK=0; CHILD_PID=""
RAM_MB=0; DISK_MB=0; VIRT=""; OS_ID=""; OS_VER=""; OS_CODENAME=""; PUBLIC_IP=""
HAVE_TTY=0; GEN_PW=0; IS_IP=0; APP_URL=""; DB_PASS=""; PHP_SOCK=""

banner() {
  local -a lines=(
    ' ____   ___  _____ _______  __'
    '|  _ \ |_ _||__  /|__  /\ \/ /'
    '| |_) | | |   / /   / /  \  / '
    '|  _ <  | |  / /_  / /_  /  \ '
    '|_| \_\|___|/____|/____|/_/\_\'
  )
  local -a grad=(51 45 39 33 27)
  local i
  echo
  for i in "${!lines[@]}"; do
    if [[ $IS_TTY == 1 ]]; then printf '   \e[1;38;5;%sm%s\e[0m\n' "${grad[$i]}" "${lines[$i]}"
    else printf '   %s\n' "${lines[$i]}"; fi
  done
  printf '   %s%sPterodactyl All-in-One Installer%s %s• v%s%s\n' "$BLD" "$MAG" "$RST" "$GRY" "$VERSION" "$RST"
  printf '   %s──────────────────────────────────────────────%s\n\n' "$GRY" "$RST"
}

ok()   { printf '  %s✔%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$YEL" "$RST" "$*"; }
bad()  { printf '  %s✘%s %s\n' "$RED" "$RST" "$*"; }
info() { printf '  %s➜%s %s\n' "$CYN" "$RST" "$*"; }
head1(){ printf '\n  %s%s%s\n\n' "$BLD" "$*" "$RST"; }
die()  { ERR_SHOWN=1; echo; bad "${RED}${BLD}$*${RST}"; echo; exit 1; }

on_exit() {
  local rc=$?
  if [[ $IS_TTY == 1 ]]; then printf '\e[?25h'; fi
  if [[ $rc -ne 0 && $ERR_SHOWN -eq 0 ]]; then
    echo; bad "Script berhenti tak terduga (kode $rc). Cek log: $LOG_FILE"
  fi
  rm -f "$API_KEY_FILE" "$NODE_STATE_FILE" 2>/dev/null || true
}
on_int() {
  if [[ -n "$CHILD_PID" ]]; then kill "$CHILD_PID" 2>/dev/null || true; fi
  ERR_SHOWN=1; echo; warn "Dibatalkan oleh user."; exit 130
}
trap on_exit EXIT
trap on_int INT TERM

usage() {
  cat <<EOF
RIZZX Pterodactyl All-in-One Installer v${VERSION}

Pemakaian: sudo bash install-panel.sh [perintah] [opsi]

Perintah:
  (kosong)   Menu interaktif
  panel      Install Panel (Nginx, PHP ${PHP_VER}, MariaDB, Redis, SSL opsional)
  wings      Install Docker + Wings (VPS node)
  full       Panel + Wings + Location & Node otomatis di satu VPS
  status     Cek kondisi Panel / Wings / service / SSL
  admin      Tambah akun admin Panel
  update     Update Panel ke rilis terbaru (backup otomatis)

Opsi umum:
  --fqdn <domain>       Domain Panel (atau IP)
  --email <email>       Email admin (default admin@<domain-utama>)
  --password <pw>       Password admin (default acak)
  --timezone <tz>       Default Asia/Jakarta
  --ssl | --no-ssl      Let's Encrypt on/off
  --version <vX.Y.Z>    Versi Panel (default latest)
  --api-key             Buat Application API key (ptla_) untuk bot/API
  --yes, -y             Tanpa pertanyaan (non-interaktif)
  --force-os            Lewati cek OS (risiko ditanggung sendiri)
  --force-ssl           Tetap coba SSL walau DNS tampak tidak cocok
  --require-ssl         Exit dengan error bila SSL gagal terbit

Opsi node (full / wings):
  --node-fqdn <domain>  FQDN node (default = FQDN Panel)
  --node-name <nama>    Nama node (default Node-RIZZX)
  --node-ram <MB>       RAM node (default total RAM - 1024)
  --location <KODE>     Kode lokasi (default ID)  --location-name <nama>
  --panel-url <url>     [wings] URL Panel jarak jauh
  --node-id <id>        [wings] ID node di Panel
  --token <ptla_...>    [wings] Application API key Panel

Env bot juga diterima: FQDN, user_email, user_password, timezone,
CONFIGURE_LETSENCRYPT.   Log: ${LOG_FILE}
EOF
}

# ── Parse argumen (dukung --opt value dan --opt=value) ───────────────────────
args=()
for a in "$@"; do
  if [[ "$a" == --*=* ]]; then args+=("${a%%=*}" "${a#*=}"); else args+=("$a"); fi
done
if ((${#args[@]})); then set -- "${args[@]}"; else set --; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    panel|wings|full|status|admin|update|menu) CMD="$1"; shift ;;
    --fqdn)          FQDN="${2:-}"; shift 2 ;;
    --email)         ADMIN_EMAIL="${2:-}"; shift 2 ;;
    --password)      ADMIN_PASSWORD="${2:-}"; shift 2 ;;
    --timezone)      TIMEZONE="${2:-}"; shift 2 ;;
    --version)       PANEL_VERSION="${2:-latest}"; shift 2 ;;
    --ssl)           ENABLE_SSL="true"; shift ;;
    --no-ssl)        ENABLE_SSL="false"; shift ;;
    --api-key)       MAKE_API_KEY="true"; shift ;;
    --yes|-y)        ASSUME_YES="true"; shift ;;
    --force-os)      FORCE_OS="true"; shift ;;
    --force-ssl)     FORCE_SSL="true"; shift ;;
    --require-ssl)   REQUIRE_SSL="true"; shift ;;
    --node-fqdn)     NODE_FQDN="${2:-}"; shift 2 ;;
    --node-name)     NODE_NAME="${2:-}"; shift 2 ;;
    --node-ram)      NODE_RAM="${2:-}"; shift 2 ;;
    --location)      LOC_SHORT="${2:-}"; shift 2 ;;
    --location-name) LOC_LONG="${2:-}"; shift 2 ;;
    --panel-url)     WINGS_PANEL_URL="${2:-}"; shift 2 ;;
    --node-id)       WINGS_NODE_ID="${2:-}"; shift 2 ;;
    --token)         WINGS_TOKEN="${2:-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) usage; die "Opsi/perintah tidak dikenal: $1" ;;
  esac
done

to_bool() {
  case "${1,,}" in
    true|yes|y|1|on) echo true ;;
    false|no|n|0|off) echo false ;;
    *) echo ask ;;
  esac
}
ENABLE_SSL="$(to_bool "$ENABLE_SSL")"
MAKE_API_KEY="$(to_bool "$MAKE_API_KEY")"; if [[ $MAKE_API_KEY == ask ]]; then MAKE_API_KEY=false; fi
ASSUME_YES="$(to_bool "$ASSUME_YES")";     if [[ $ASSUME_YES == ask ]]; then ASSUME_YES=false; fi
FORCE_OS="$(to_bool "$FORCE_OS")";         if [[ $FORCE_OS == ask ]]; then FORCE_OS=false; fi
FORCE_SSL="$(to_bool "$FORCE_SSL")";       if [[ $FORCE_SSL == ask ]]; then FORCE_SSL=false; fi
REQUIRE_SSL="$(to_bool "$REQUIRE_SSL")";   if [[ $REQUIRE_SSL == ask ]]; then REQUIRE_SSL=false; fi

# ── Input interaktif (baca dari /dev/tty → aman untuk `bash <(curl ...)`) ────
if [[ $ASSUME_YES != true ]] && (exec </dev/tty) 2>/dev/null; then HAVE_TTY=1; fi

prompt() { # prompt VAR "Pertanyaan" "default" [secret]
  local var="$1" q="$2" def="${3:-}" secret="${4:-}" in=""
  if [[ $HAVE_TTY != 1 ]]; then printf -v "$var" '%s' "$def"; return 0; fi
  local hint=""; if [[ -n "$def" && -z "$secret" ]]; then hint=" ${GRY}[$def]${RST}"; fi
  printf '  %s?%s %s%s: ' "$MAG" "$RST" "$q" "$hint" >/dev/tty
  if [[ -n "$secret" ]]; then read -r -s in </dev/tty || true; echo >/dev/tty
  else read -r in </dev/tty || true; fi
  printf -v "$var" '%s' "${in:-$def}"
}
confirm() { # confirm "Pertanyaan" default(y/n)
  local q="$1" def="${2:-y}" ans=""
  if [[ $HAVE_TTY != 1 ]]; then [[ $def == y ]]; return; fi
  prompt ans "$q (y/n)" "$def"
  [[ "${ans,,}" == y* ]]
}
rand_str() {
  local n="${1:-24}" s=""
  s="$(openssl rand -base64 $((n * 3)) | tr -dc 'A-Za-z0-9' | head -c "$n" || true)"
  printf '%s' "$s"
}
bar() { # bar persen -> ▰▰▰▱▱▱
  local pct="$1" w=12 f i out=""
  f=$(( pct * w / 100 ))
  for ((i = 0; i < w; i++)); do if (( i < f )); then out+="▰"; else out+="▱"; fi; done
  printf '%s' "$out"
}
dl() { curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 -o "$2" "$1"; }

# ── Runner step dengan spinner + progress bar ────────────────────────────────
run_step() { # run_step [-s] "Label" fungsi [arg...]   (-s = soft: gagal tidak menghentikan script)
  local soft=0; if [[ "$1" == "-s" ]]; then soft=1; shift; fi
  local label="$1"; shift
  STEP_NUM=$((STEP_NUM + 1))
  local tag pct start=$SECONDS rc=0 i=0
  tag="$(printf '%02d/%02d' "$STEP_NUM" "$STEP_TOTAL")"
  pct=$(( STEP_NUM * 100 / STEP_TOTAL ))
  printf '\n### [%s] %s\n' "$tag" "$label" >>"$LOG_FILE"
  ( set -Eeuo pipefail; "$@" ) >>"$LOG_FILE" 2>&1 &
  CHILD_PID=$!
  if [[ $IS_TTY == 1 ]]; then
    printf '\e[?25l'
    while kill -0 "$CHILD_PID" 2>/dev/null; do
      printf '\r\e[2K  %s%s%s %s[%s]%s %s %s%ss%s' "$CYN" "${SPIN[i % 10]}" "$RST" "$GRY" "$tag" "$RST" "$label" "$GRY" "$((SECONDS - start))" "$RST"
      i=$((i + 1)); sleep 0.1
    done
    printf '\e[?25h'
  else
    printf '  … [%s] %s\n' "$tag" "$label"
  fi
  wait "$CHILD_PID" || rc=$?
  CHILD_PID=""
  local took=$((SECONDS - start))
  if [[ $rc -eq 0 ]]; then
    printf '%s  %s✔%s %s[%s]%s %s %s(%ss) %s %s%%%s\n' "$CLR" "$GRN" "$RST" "$GRY" "$tag" "$RST" "$label" "$GRY" "$took" "$(bar "$pct")" "$pct" "$RST"
    return 0
  fi
  if [[ $soft -eq 1 ]]; then
    printf '%s  %s⚠%s %s[%s]%s %s %s(dilewati, kode %s)%s\n' "$CLR" "$YEL" "$RST" "$GRY" "$tag" "$RST" "$label" "$GRY" "$rc" "$RST"
    return "$rc"
  fi
  printf '%s  %s✘%s %s[%s]%s %s\n' "$CLR" "$RED" "$RST" "$GRY" "$tag" "$RST" "$label"
  echo; echo "  ${RED}${BLD}── 20 baris log terakhir ──${RST}"
  tail -n 20 "$LOG_FILE" | sed 's/^/    /'
  echo
  ERR_SHOWN=1
  bad "Gagal di langkah: $label"
  info "Log lengkap : $LOG_FILE"
  info "Perbaiki masalahnya lalu jalankan ulang. Tidak ada data yang dihapus otomatis."
  exit 1
}

chk_total=0; chk_fail=0
chk() { # chk "label" perintah...
  local label="$1"; shift
  chk_total=$((chk_total + 1))
  if "$@" >>"$LOG_FILE" 2>&1; then ok "$label"; else bad "$label"; chk_fail=$((chk_fail + 1)); fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT
# ══════════════════════════════════════════════════════════════════════════════
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
APT=(apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o DPkg::Lock::Timeout=300 -o Acquire::Retries=5)

wait_apt() {
  local i=0
  while pgrep -x 'apt|apt-get|dpkg|aptitude|unattended-upgr' >/dev/null 2>&1; do
    i=$((i + 1)); if [[ $i -gt 100 ]]; then break; fi
    sleep 3
  done
}
apt_run() { wait_apt; "${APT[@]}" "$@"; }

need_root() { [[ $EUID -eq 0 ]] || die "Jalankan sebagai root:  sudo bash $0"; }
init_log()  { mkdir -p "$(dirname "$LOG_FILE")"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"; printf '\n===== %s • %s =====\n' "$(date '+%F %T')" "${CMD:-menu}" >>"$LOG_FILE"; }
panel_installed() { [[ -f "$PTERO_DIR/artisan" && -f "$PTERO_DIR/.env" ]]; }
wings_installed() { [[ -x /usr/local/bin/wings ]]; }
mysql_cli() { command -v mariadb || command -v mysql; }

port_owner() {
  command -v ss >/dev/null 2>&1 || return 0
  ss -H -tlnp "sport = :$1" 2>/dev/null | grep -o '"[^"]*"' | head -n1 | tr -d '"' || true
}

preflight_common() { # $1 = label mode: panel | wings
  local mode="$1"
  head1 "Pre-flight check"
  [[ -r /etc/os-release ]] || die "/etc/os-release tidak ditemukan; OS tidak dikenali."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-?}"; OS_VER="${VERSION_ID:-?}"; OS_CODENAME="${VERSION_CODENAME:-}"
  local supported=0
  case "$OS_ID:$OS_VER" in ubuntu:22.04|ubuntu:24.04|debian:11|debian:12) supported=1 ;; esac
  if [[ $supported == 1 ]]; then ok "OS didukung: ${PRETTY_NAME:-$OS_ID $OS_VER}"
  elif [[ $FORCE_OS == true ]]; then warn "OS tidak resmi didukung (${OS_ID} ${OS_VER}), lanjut karena --force-os"
  else die "OS ${OS_ID} ${OS_VER} tidak didukung. Pakai Ubuntu 22.04/24.04 atau Debian 11/12 (atau --force-os)."; fi
  [[ -n "$OS_CODENAME" ]] || OS_CODENAME="$(lsb_release -sc 2>/dev/null || true)"

  local arch; arch="$(uname -m)"
  case "$arch" in x86_64|aarch64) ok "Arsitektur: $arch" ;; *) die "Arsitektur $arch tidak didukung." ;; esac

  VIRT="$(systemd-detect-virt 2>/dev/null || true)"
  case "$VIRT" in
    openvz)
      if [[ $mode == wings ]]; then die "OpenVZ tidak bisa menjalankan Docker/Wings. Pakai KVM/dedicated."; fi
      warn "Virtualisasi openvz: Panel jalan, tetapi Wings/Docker tidak bisa di VPS ini." ;;
    lxc|lxc-libvirt)
      warn "Virtualisasi $VIRT: Docker/Wings sering bermasalah di container LXC." ;;
  esac

  RAM_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  DISK_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
  if   (( RAM_MB < 900 ));  then die "RAM ${RAM_MB} MB terlalu kecil (minimal 1 GB, disarankan 2 GB)."
  elif (( RAM_MB < 1800 )); then warn "RAM ${RAM_MB} MB (disarankan 2 GB). Swap otomatis akan ditambahkan bila perlu."
  else ok "RAM: ${RAM_MB} MB"; fi
  if   (( DISK_MB < 3000 )); then die "Disk kosong ${DISK_MB} MB terlalu kecil (minimal 3 GB)."
  elif (( DISK_MB < 5120 )); then warn "Disk kosong ${DISK_MB} MB (disarankan > 5 GB)."
  else ok "Disk kosong: ${DISK_MB} MB"; fi

  if ! command -v curl >/dev/null 2>&1; then
    info "Memasang curl dulu..."
    { apt-get update -q && apt_run install curl ca-certificates; } >>"$LOG_FILE" 2>&1 || die "Gagal memasang curl."
  fi
  curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1 || die "Tidak bisa menjangkau github.com (cek internet/DNS/firewall VPS)."
  ok "Koneksi internet / GitHub OK"
  PUBLIC_IP="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || curl -fsS4 --max-time 6 https://ifconfig.me 2>/dev/null || true)"
}

preflight_panel() {
  if panel_installed; then
    die "Panel sudah terpasang di $PTERO_DIR. Dibatalkan agar database/config lama tidak tertimpa. (Gunakan: update)"
  fi
  if [[ -d "$PTERO_DIR" ]] && [[ -n "$(ls -A "$PTERO_DIR" 2>/dev/null)" ]]; then
    die "Direktori $PTERO_DIR sudah ada dan tidak kosong. Pindahkan/hapus dulu secara manual."
  fi
  ok "Belum ada Panel di $PTERO_DIR"
  local p owner
  for p in 80 443; do
    owner="$(port_owner "$p")"
    if [[ -n "$owner" && "$owner" != "nginx" ]]; then
      die "Port $p dipakai oleh '$owner'. Hentikan dulu (mis. systemctl disable --now $owner) lalu jalankan ulang."
    fi
  done
  ok "Port 80/443 tersedia"
}

# ══════════════════════════════════════════════════════════════════════════════
#  KONFIGURASI (interaktif / flag)
# ══════════════════════════════════════════════════════════════════════════════
IPV4_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
HOST_RE='^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$'

dns_matches() { # dns_matches fqdn -> 0 cocok, 1 tidak
  local d; d="$(getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
  if [[ -z "$d" ]]; then warn "Domain $1 belum resolve ke IP mana pun."; return 1; fi
  if [[ -n "$PUBLIC_IP" && "$d" != "$PUBLIC_IP" ]]; then
    warn "Domain $1 → $d, tetapi IP VPS ini $PUBLIC_IP (matikan proxy Cloudflare / pakai DNS-only)."; return 1
  fi
  ok "DNS $1 → $d (cocok dengan VPS)"; return 0
}

gather_panel_config() {
  head1 "Konfigurasi Panel"
  if [[ -z "$FQDN" ]]; then
    [[ $HAVE_TTY == 1 ]] || die "FQDN wajib. Pakai --fqdn panel.domain.com"
    prompt FQDN "Domain Panel (mis. panel.domain.com atau IP)" ""
  fi
  FQDN="${FQDN,,}"; FQDN="${FQDN#http://}"; FQDN="${FQDN#https://}"; FQDN="${FQDN%%/*}"
  IS_IP=0
  if   [[ $FQDN =~ $IPV4_RE ]]; then IS_IP=1
  elif [[ ! $FQDN =~ $HOST_RE ]]; then die "FQDN '$FQDN' tidak valid."; fi

  if [[ -z "$ADMIN_EMAIL" ]]; then
    local def_mail
    if [[ $IS_IP == 1 ]]; then def_mail="admin@example.com"; else def_mail="admin@$(awk -F. '{print $(NF-1)"."$NF}' <<<"$FQDN")"; fi
    prompt ADMIN_EMAIL "Email admin" "$def_mail"
  fi
  [[ $ADMIN_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Email '$ADMIN_EMAIL' tidak valid."
  [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Timezone '$TIMEZONE' tidak valid (contoh: Asia/Jakarta)."

  if [[ -z "$ADMIN_PASSWORD" && $HAVE_TTY == 1 ]]; then prompt ADMIN_PASSWORD "Password admin (kosong = acak)" "" secret; fi
  GEN_PW=0
  if [[ -z "$ADMIN_PASSWORD" ]]; then ADMIN_PASSWORD="$(rand_str 20)"; GEN_PW=1; fi
  (( ${#ADMIN_PASSWORD} >= 8 )) || die "Password admin minimal 8 karakter."

  if [[ $IS_IP == 1 ]]; then
    if [[ $ENABLE_SSL == true ]]; then warn "SSL tidak bisa dipakai untuk alamat IP, dinonaktifkan."; fi
    ENABLE_SSL=false
  elif [[ $ENABLE_SSL == ask ]]; then
    if [[ $HAVE_TTY != 1 ]]; then ENABLE_SSL=false
    elif confirm "Aktifkan SSL Let's Encrypt (HTTPS)?" y; then ENABLE_SSL=true
    else ENABLE_SSL=false; fi
  fi
  if [[ $ENABLE_SSL == true ]]; then
    if ! dns_matches "$FQDN"; then
      if [[ $FORCE_SSL == true ]]; then warn "Lanjut mencoba SSL karena --force-ssl."
      elif ! confirm "Tetap coba SSL?" n; then ENABLE_SSL=false; warn "SSL dilewati. Panel akan dipasang via HTTP."; fi
    fi
  fi
  if [[ $ENABLE_SSL == true ]]; then APP_URL="https://$FQDN"; else APP_URL="http://$FQDN"; fi
}

gather_node_config() {
  head1 "Konfigurasi Node"
  if [[ -z "$NODE_FQDN" ]]; then NODE_FQDN="$FQDN"; fi
  NODE_FQDN="${NODE_FQDN,,}"
  if [[ ! $NODE_FQDN =~ $HOST_RE && ! $NODE_FQDN =~ $IPV4_RE ]]; then die "FQDN node '$NODE_FQDN' tidak valid."; fi
  [[ $LOC_SHORT =~ ^[A-Za-z0-9._-]{1,60}$ ]] || die "Kode lokasi '$LOC_SHORT' tidak valid (huruf/angka/._- maks 60)."
  [[ -n "$NODE_NAME" ]] || die "Nama node kosong."
  if [[ -z "$NODE_RAM" ]]; then NODE_RAM=$(( RAM_MB - 1024 )); fi
  [[ $NODE_RAM =~ ^[0-9]+$ ]] || die "--node-ram harus angka (MB)."
  if (( NODE_RAM < 512 )); then NODE_RAM=512; fi
  ok "Node: $NODE_NAME @ $NODE_FQDN  (RAM ${NODE_RAM} MB, lokasi ${LOC_SHORT})"
  if [[ "$NODE_FQDN" != "$FQDN" && $ENABLE_SSL == true ]]; then dns_matches "$NODE_FQDN" || true; fi
}

summary_box() { # summary_box "baris" ...
  printf '\n  %s┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓%s\n' "$MAG" "$RST"
  local l; for l in "$@"; do printf '  %s┃%s  %s\n' "$MAG" "$RST" "$l"; done
  printf '  %s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%s\n\n' "$MAG" "$RST"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LANGKAH-LANGKAH PANEL (jalan di subshell via run_step; output → log)
# ══════════════════════════════════════════════════════════════════════════════
ensure_swap() {
  local swap; swap="$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)"
  if (( RAM_MB < 2000 && swap == 0 && DISK_MB > 6000 )) && [[ "$VIRT" != openvz && "$VIRT" != lxc* && ! -e /swapfile ]]; then
    echo "RAM kecil & tanpa swap: membuat /swapfile 2G agar Composer tidak OOM"
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  fi
  return 0
}

step_base() {
  wait_apt
  dpkg --configure -a || true
  apt_run --fix-broken install || true
  apt_run update
  apt_run install ca-certificates curl gnupg lsb-release apt-transport-https \
    tar unzip git cron openssl iproute2 procps
  if [[ "$OS_ID" == "ubuntu" ]]; then apt_run install software-properties-common; fi
  ensure_swap
}

step_php_repo() {
  case "$OS_ID" in
    ubuntu)
      if [[ "$OS_VER" == "24.04" ]]; then echo "Ubuntu 24.04: PHP ${PHP_VER} sudah ada di repo resmi."
      else LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php; fi ;;
    debian)
      if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
        dl https://packages.sury.org/debsuryorg-archive-keyring.deb /tmp/debsuryorg-archive-keyring.deb
        dpkg -i /tmp/debsuryorg-archive-keyring.deb
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ ${OS_CODENAME} main" >/etc/apt/sources.list.d/php.list
        rm -f /tmp/debsuryorg-archive-keyring.deb
      fi ;;
  esac
  apt_run update
}

step_php() {
  # Sengaja TIDAK memasang meta-paket "php8.3" (bisa menarik Apache).
  apt_run install "php${PHP_VER}-cli" "php${PHP_VER}-fpm" "php${PHP_VER}-common" "php${PHP_VER}-gd" \
    "php${PHP_VER}-mysql" "php${PHP_VER}-mbstring" "php${PHP_VER}-bcmath" "php${PHP_VER}-xml" \
    "php${PHP_VER}-curl" "php${PHP_VER}-zip" "php${PHP_VER}-intl"
  update-alternatives --set php "/usr/bin/php${PHP_VER}" 2>/dev/null || true
  systemctl enable --now "php${PHP_VER}-fpm"
  php -v
}

step_services() {
  apt_run install mariadb-server redis-server nginx cron
  systemctl enable --now mariadb redis-server nginx cron
}

step_composer() {
  dl https://getcomposer.org/download/latest-2.x/composer.phar /usr/local/bin/composer
  chmod +x /usr/local/bin/composer
  COMPOSER_ALLOW_SUPERUSER=1 composer --version
}

panel_tar_url() {
  if [[ "$PANEL_VERSION" == "latest" ]]; then echo "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
  else echo "https://github.com/pterodactyl/panel/releases/download/${PANEL_VERSION}/panel.tar.gz"; fi
}

step_download() {
  mkdir -p "$PTERO_DIR"
  dl "$(panel_tar_url)" /tmp/rizzx-panel.tar.gz
  tar -xzf /tmp/rizzx-panel.tar.gz -C "$PTERO_DIR"
  rm -f /tmp/rizzx-panel.tar.gz
  cd "$PTERO_DIR"
  [[ -f artisan ]] || { echo "artisan tidak ditemukan setelah extract"; return 1; }
  chmod -R 755 storage/* bootstrap/cache/
  cp .env.example .env
}

step_database() {
  local mysql_bin existing
  mysql_bin="$(mysql_cli)"
  existing="$("$mysql_bin" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")"
  if [[ "${existing:-0}" -gt 0 ]]; then
    echo "Database '${DB_NAME}' sudah berisi ${existing} tabel. Dibatalkan agar data lama tidak rusak."
    return 1
  fi
  "$mysql_bin" <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
}

step_composer_install() {
  cd "$PTERO_DIR"
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
}

step_configure() {
  cd "$PTERO_DIR"
  php artisan key:generate --force
  php artisan p:environment:setup \
    --author="$ADMIN_EMAIL" --url="$APP_URL" --timezone="$TIMEZONE" \
    --cache=redis --session=redis --queue=redis \
    --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379 \
    --settings-ui=true --telemetry=false --no-interaction
  php artisan p:environment:database \
    --host=127.0.0.1 --port=3306 --database="$DB_NAME" \
    --username="$DB_USER" --password="$DB_PASS" --no-interaction
  php artisan migrate --seed --force
}

step_admin() {
  cd "$PTERO_DIR"
  php artisan p:user:make \
    --email="$ADMIN_EMAIL" --username="$ADMIN_USER" \
    --name-first="$ADMIN_FIRST" --name-last="$ADMIN_LAST" \
    --password="$ADMIN_PASSWORD" --admin=1
}

step_runtime() {
  chown -R www-data:www-data "$PTERO_DIR"
  { crontab -u www-data -l 2>/dev/null | grep -v 'artisan schedule:run' || true
    echo "* * * * * php ${PTERO_DIR}/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -u www-data -
  cat >/etc/systemd/system/pteroq.service <<EOF
# Pterodactyl Queue Worker File
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php ${PTERO_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now pteroq.service
}

# ── Template Nginx (HTTP & HTTPS berbagi body yang sama) ─────────────────────
nginx_body() {
  cat <<'EOF'
    root __ROOT__/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:__PHPSOCK__;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
EOF
}

nginx_sub() { sed -e "s|__FQDN__|${FQDN}|g" -e "s|__ROOT__|${PTERO_DIR}|g" -e "s|__PHPSOCK__|${PHP_SOCK}|g"; }

render_nginx_http() {
  { echo "server {"
    echo "    listen 80;"
    echo "    listen [::]:80;"
    echo "    server_name __FQDN__;"
    echo
    nginx_body
    echo "}"
  } | nginx_sub
}

render_nginx_ssl() {
  { cat <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name __FQDN__;

    location ^~ /.well-known/acme-challenge/ {
        root __ROOT__/public;
        try_files $uri =404;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name __FQDN__;

    ssl_certificate /etc/letsencrypt/live/__FQDN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__FQDN__/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

EOF
    nginx_body
    echo "}"
  } | nginx_sub
}

step_nginx() {
  rm -f /etc/nginx/sites-enabled/default
  render_nginx_http >/etc/nginx/sites-available/pterodactyl.conf
  ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  nginx -t
  systemctl reload nginx
}

step_ssl() {
  apt_run install certbot
  certbot certonly --webroot -w "${PTERO_DIR}/public" -d "$FQDN" \
    --non-interactive --agree-tos --register-unsafely-without-email --no-eff-email \
    --keep-until-expiring --deploy-hook "systemctl reload nginx"
  [[ -f "/etc/letsencrypt/live/${FQDN}/fullchain.pem" ]] || { echo "sertifikat tidak terbentuk"; return 1; }
  cp /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf.http.bak
  render_nginx_ssl >/etc/nginx/sites-available/pterodactyl.conf
  if ! nginx -t; then
    echo "nginx -t gagal dengan config SSL, mengembalikan config HTTP"
    cp /etc/nginx/sites-available/pterodactyl.conf.http.bak /etc/nginx/sites-available/pterodactyl.conf
    return 1
  fi
  systemctl reload nginx
  systemctl enable --now certbot.timer 2>/dev/null || true
}

step_api_key() {
  cd "$PTERO_DIR"
  local tmp out; tmp="$(mktemp /tmp/.rizzx-api-XXXXXX.php)"
  cat >"$tmp" <<'PHP'
<?php
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
$user = Pterodactyl\Models\User::query()->where('username', 'admin')->where('root_admin', 1)->first();
if (!$user) { fwrite(STDERR, 'ADMIN_NOT_FOUND'); exit(20); }
$service = $app->make(Pterodactyl\Services\Api\KeyCreationService::class);
$type = Pterodactyl\Models\ApiKey::TYPE_APPLICATION;
$permissions = [];
foreach (Pterodactyl\Services\Acl\Api\AdminAcl::getResourceList() as $resource) { $permissions['r_' . $resource] = 3; }
$key = $service->setKeyType($type)->handle(['memo' => 'Rizzx Installer API key', 'user_id' => $user->id], $permissions);
echo 'RIZZX_API_KEY_BEGIN:' . $key->identifier . decrypt($key->token) . ':RIZZX_API_KEY_END';
PHP
  out="$(php "$tmp")"; rm -f "$tmp"
  [[ "$out" =~ RIZZX_API_KEY_BEGIN:(ptla_[A-Za-z0-9_-]+):RIZZX_API_KEY_END ]] || { echo "format API key tidak dikenali"; return 1; }
  ( umask 077; printf '%s' "${BASH_REMATCH[1]}" >"$API_KEY_FILE" )
}

step_finalize() {
  cd "$PTERO_DIR"
  local final_url
  if [[ "$SSL_OK" == 1 ]]; then final_url="https://${FQDN}"; else final_url="http://${FQDN}"; fi
  sed -i "s|^APP_URL=.*|APP_URL=${final_url}|" .env
  php artisan optimize:clear || true
  chown -R www-data:www-data "$PTERO_DIR"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    ufw allow 80/tcp; ufw allow 443/tcp
  fi
  systemctl restart "php${PHP_VER}-fpm" pteroq.service
  systemctl reload nginx
}

# ══════════════════════════════════════════════════════════════════════════════
#  LANGKAH-LANGKAH WINGS & NODE
# ══════════════════════════════════════════════════════════════════════════════
step_docker() {
  if command -v docker >/dev/null 2>&1; then echo "Docker sudah terpasang"
  else
    dl https://get.docker.com /tmp/get-docker.sh
    CHANNEL=stable sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  systemctl enable --now docker
  docker --version
}

step_wings_bin() {
  local arch
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) echo "arsitektur tidak didukung"; return 1 ;; esac
  systemctl stop wings 2>/dev/null || true
  mkdir -p /etc/pterodactyl /var/lib/pterodactyl/volumes /var/log/pterodactyl /tmp/pterodactyl
  dl "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}" /usr/local/bin/wings
  chmod u+x /usr/local/bin/wings
  cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  /usr/local/bin/wings --version || true
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    ufw allow 8080/tcp; ufw allow 2022/tcp
  fi
}

# Sertifikat untuk FQDN node (domain berbeda dari Panel)
step_node_ssl() {
  apt_run install certbot
  if [[ -d "$PTERO_DIR/public" && "$(port_owner 80)" == "nginx" ]]; then
    certbot certonly --webroot -w "${PTERO_DIR}/public" -d "$NODE_FQDN" \
      --non-interactive --agree-tos --register-unsafely-without-email --no-eff-email --keep-until-expiring
  else
    certbot certonly --standalone -d "$NODE_FQDN" \
      --non-interactive --agree-tos --register-unsafely-without-email --no-eff-email --keep-until-expiring
  fi
  [[ -f "/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem" ]]
}

# Buat Location + Node langsung lewat artisan, lalu tulis /etc/pterodactyl/config.yml
step_node_create() {
  cd "$PTERO_DIR"
  local mysql_bin loc_id node_id scheme disk cfg
  mysql_bin="$(mysql_cli)"
  scheme=http
  if [[ -f "/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem" ]]; then scheme=https; fi
  disk=$(( $(df -Pm / | awk 'NR==2 {print $4}') * 90 / 100 ))

  php artisan p:location:make --short="$LOC_SHORT" --long="$LOC_LONG" --no-interaction
  loc_id="$("$mysql_bin" -N -e "SELECT id FROM ${DB_NAME}.locations WHERE short='${LOC_SHORT}' ORDER BY id DESC LIMIT 1;")"
  [[ -n "$loc_id" ]] || { echo "location id tidak ditemukan"; return 1; }

  php artisan p:node:make \
    --name="$NODE_NAME" --description="Node otomatis RIZZX" --locationId="$loc_id" \
    --fqdn="$NODE_FQDN" --public=1 --scheme="$scheme" --proxy=0 \
    --maxMemory="$NODE_RAM" --overallocateMemory=0 \
    --maxDisk="$disk" --overallocateDisk=0 --uploadSize=100 \
    --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes \
    --no-interaction
  node_id="$("$mysql_bin" -N -e "SELECT id FROM ${DB_NAME}.nodes WHERE fqdn='${NODE_FQDN}' ORDER BY id DESC LIMIT 1;")"
  [[ -n "$node_id" ]] || { echo "node id tidak ditemukan"; return 1; }

  cfg="$(mktemp /tmp/.rizzx-wings-XXXXXX.yml)"
  # Cara 1: perintah artisan resmi.
  if ! php artisan p:node:configuration "$node_id" >"$cfg" 2>/dev/null || ! grep -q 'uuid:' "$cfg"; then
    echo "p:node:configuration tidak tersedia, pakai fallback Eloquent"
    cat >"${cfg}.php" <<'PHP'
<?php
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();
$node = Pterodactyl\Models\Node::findOrFail((int) getenv('RIZZX_NODE_ID'));
echo json_encode($node->getConfiguration(), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
PHP
    RIZZX_NODE_ID="$node_id" php "${cfg}.php" >"$cfg"
    rm -f "${cfg}.php"
    grep -q '"uuid"' "$cfg" || { echo "gagal membuat config Wings"; rm -f "$cfg"; return 1; }
  fi
  mkdir -p /etc/pterodactyl
  install -m 600 "$cfg" /etc/pterodactyl/config.yml
  rm -f "$cfg"
  ( umask 077; echo "$node_id" >"$NODE_STATE_FILE" )
  chown -R www-data:www-data "$PTERO_DIR"
}

step_wings_configure() { # untuk Wings di VPS terpisah: pakai `wings configure`
  cd /etc/pterodactyl
  /usr/local/bin/wings configure --panel-url "$WINGS_PANEL_URL" --token "$WINGS_TOKEN" --node "$WINGS_NODE_ID"
  [[ -s /etc/pterodactyl/config.yml ]]
}

step_wings_start() {
  systemctl daemon-reload
  if [[ -s /etc/pterodactyl/config.yml ]]; then
    systemctl enable --now wings
    sleep 3
    systemctl is-active --quiet wings
  else
    systemctl enable wings
    echo "config.yml belum ada; Wings di-enable tapi belum dijalankan."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  VALIDASI
# ══════════════════════════════════════════════════════════════════════════════
http_ok() {
  local code
  if [[ $SSL_OK == 1 ]]; then
    code="$(curl -ksS --max-time 20 --resolve "${FQDN}:443:127.0.0.1" -o /dev/null -w '%{http_code}' "https://${FQDN}/auth/login" || true)"
  else
    code="$(curl -sS --max-time 20 -H "Host: ${FQDN}" -o /dev/null -w '%{http_code}' "http://127.0.0.1/auth/login" || true)"
  fi
  [[ "$code" =~ ^[23] ]]
}
admin_ok() {
  local cnt; cnt="$("$(mysql_cli)" -N -e "SELECT COUNT(*) FROM ${DB_NAME}.users WHERE username='${ADMIN_USER}' AND root_admin=1;")"
  [[ "$cnt" == "1" ]]
}
validate_panel() {
  head1 "Validasi Panel"
  chk "File .env Panel ada"                      test -f "$PTERO_DIR/.env"
  chk "APP_KEY ter-generate"                     grep -Eq '^APP_KEY=base64:' "$PTERO_DIR/.env"
  chk "php artisan p:info (DB & Redis OK)"       bash -c "cd '$PTERO_DIR' && php artisan p:info"
  chk "User admin (root_admin) ada di database"  admin_ok
  chk "Service nginx aktif"                      systemctl is-active --quiet nginx
  chk "Service php${PHP_VER}-fpm aktif"          systemctl is-active --quiet "php${PHP_VER}-fpm"
  chk "Service mariadb aktif"                    systemctl is-active --quiet mariadb
  chk "Service redis aktif"                      systemctl is-active --quiet redis-server
  chk "Service pteroq aktif"                     systemctl is-active --quiet pteroq.service
  chk "Panel menjawab HTTP (/auth/login)"        http_ok
}
validate_wings() {
  head1 "Validasi Wings"
  chk "Docker aktif"              systemctl is-active --quiet docker
  chk "Binary Wings terpasang"    test -x /usr/local/bin/wings
  if [[ -s /etc/pterodactyl/config.yml ]]; then
    chk "Service wings aktif"     systemctl is-active --quiet wings
    chk "Wings listen di :8080"   bash -c "ss -tln | grep -q ':8080 '"
  else
    warn "Wings belum punya config.yml (belum dikonfigurasi dari Panel)."
  fi
}

write_creds() {
  local api="" node=""
  if [[ -s "$API_KEY_FILE" ]]; then api="$(cat "$API_KEY_FILE")"; fi
  if [[ -s "$NODE_STATE_FILE" ]]; then node="$(cat "$NODE_STATE_FILE")"; fi
  local node_txt="(tidak dibuat)"
  if [[ -n "$node" ]]; then node_txt="ID ${node} @ ${NODE_FQDN}"; fi
  ( umask 077
    cat >"$CRED_FILE" <<EOF
RIZZX Pterodactyl - $(date '+%Y-%m-%d %H:%M:%S')
Panel URL      : ${APP_URL}
Admin username : ${ADMIN_USER}
Admin email    : ${ADMIN_EMAIL}
Admin password : ${ADMIN_PASSWORD}
DB name / user : ${DB_NAME} / ${DB_USER}
DB password    : ${DB_PASS}
Panel path     : ${PTERO_DIR}
App API key    : ${api:-"(tidak dibuat; pakai --api-key bila perlu)"}
Node           : ${node_txt}
EOF
  )
}

# ══════════════════════════════════════════════════════════════════════════════
#  PERINTAH
# ══════════════════════════════════════════════════════════════════════════════
panel_step_count() {
  local n=13
  if [[ $ENABLE_SSL == true ]]; then n=$((n + 1)); fi
  if [[ $MAKE_API_KEY == true ]]; then n=$((n + 1)); fi
  echo "$n"
}

run_panel_steps() {
  PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
  DB_PASS="$(rand_str 32)"
  run_step "Update sistem & paket dasar"                    step_base
  run_step "Menyiapkan repo PHP ${PHP_VER}"                  step_php_repo
  run_step "Memasang PHP ${PHP_VER} + ekstensi"              step_php
  run_step "Memasang MariaDB, Redis, Nginx"                  step_services
  run_step "Memasang Composer"                               step_composer
  run_step "Mengunduh Pterodactyl Panel (${PANEL_VERSION})"  step_download
  run_step "Membuat database & user MariaDB"                 step_database
  run_step "Composer install (dependensi Panel)"             step_composer_install
  run_step "Konfigurasi environment & migrasi DB"            step_configure
  run_step "Membuat akun admin"                              step_admin
  run_step "Service queue (pteroq) & cron"                   step_runtime
  run_step "Konfigurasi vhost Nginx"                         step_nginx
  if [[ $ENABLE_SSL == true ]]; then
    if run_step -s "Menerbitkan SSL Let's Encrypt" step_ssl; then SSL_OK=1; fi
  fi
  if [[ $MAKE_API_KEY == true ]]; then run_step -s "Membuat Application API key" step_api_key || true; fi
  run_step "Finalisasi (APP_URL, cache, restart)"            step_finalize
  if [[ $SSL_OK == 1 ]]; then APP_URL="https://$FQDN"; else APP_URL="http://$FQDN"; fi
  if [[ $ENABLE_SSL == true && $SSL_OK != 1 ]]; then
    warn "SSL gagal diterbitkan; Panel berjalan via HTTP. Cek DNS lalu coba: certbot certonly --webroot -w ${PTERO_DIR}/public -d ${FQDN}"
    if [[ $REQUIRE_SSL == true ]]; then
      die "SSL wajib (--require-ssl) tetapi gagal terbit. Panel sudah terpasang via HTTP; perbaiki DNS/port 80 lalu terbitkan sertifikat manual."
    fi
  fi
}

panel_summary() {
  local api=""; if [[ -s "$API_KEY_FILE" ]]; then api="$(cat "$API_KEY_FILE")"; fi
  echo
  if [[ $chk_fail -eq 0 ]]; then printf '  %s%s┏━━ 🎉  PANEL SIAP DIPAKAI  (%ss) ━━━━━━━━━━━━━━━━━┓%s\n' "$BLD" "$GRN" "$1" "$RST"
  else printf '  %s%s┏━━ ⚠  SELESAI DENGAN %s PERINGATAN (cek log) ━━━━━┓%s\n' "$BLD" "$YEL" "$chk_fail" "$RST"; fi
  printf '  %s┃%s  %-15s %s%s%s\n' "$GRN" "$RST" "Panel URL"   "$CYN" "$APP_URL" "$RST"
  printf '  %s┃%s  %-15s %s\n'     "$GRN" "$RST" "Username"    "$ADMIN_USER"
  printf '  %s┃%s  %-15s %s\n'     "$GRN" "$RST" "Email"       "$ADMIN_EMAIL"
  printf '  %s┃%s  %-15s %s%s%s\n' "$GRN" "$RST" "Password"    "$YEL" "$ADMIN_PASSWORD" "$RST"
  printf '  %s┃%s  %-15s %s\n'     "$GRN" "$RST" "DB password" "$DB_PASS"
  if [[ -n "$api" ]]; then printf '  %s┃%s  %-15s %s\n' "$GRN" "$RST" "API key (ptla)" "$api"; fi
  printf '  %s┃%s\n' "$GRN" "$RST"
  printf '  %s┃%s  %s💾 Kredensial : %s (chmod 600)%s\n' "$GRN" "$RST" "$GRY" "$CRED_FILE" "$RST"
  printf '  %s┃%s  %s📜 Log        : %s%s\n'             "$GRN" "$RST" "$GRY" "$LOG_FILE" "$RST"
  printf '  %s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%s\n' "$GRN" "$RST"
  echo
}

bot_note() {
  head1 "Opsional: integrasi bot RIZZX V8"
  info "Admin ${BLD}${ADMIN_USER}${RST} (ID 1) cocok dengan PROTECT_ROOT_ADMIN_ID=1 dan pembuat API key bot."
  info "Isi PTERODACTYL_APPLICATION_API_KEY di .env bot dengan key dari --api-key, atau kosongkan agar bot membuat sendiri."
  info "Jangan jalankan /installpanel bot di VPS ini (bot menolak karena Panel sudah ada)."
}

cmd_panel() {
  init_log; preflight_common panel; preflight_panel; gather_panel_config
  STEP_TOTAL="$(panel_step_count)"
  summary_box "$(printf '%-12s %s' 'Panel URL' "$APP_URL")" "$(printf '%-12s %s' 'Admin' "$ADMIN_USER <$ADMIN_EMAIL>")" \
    "$(printf '%-12s %s' 'Timezone' "$TIMEZONE")" "$(printf '%-12s %s' 'SSL' "$ENABLE_SSL")" "$(printf '%-12s %s' 'Panel' "$PANEL_VERSION / PHP $PHP_VER")"
  if [[ $HAVE_TTY == 1 ]]; then confirm "Mulai instalasi sekarang?" y || { ERR_SHOWN=1; warn "Dibatalkan."; exit 0; }; fi
  head1 "Instalasi berjalan  ${GRY}(log: $LOG_FILE)"
  local t0=$SECONDS
  run_panel_steps
  validate_panel
  write_creds
  panel_summary "$((SECONDS - t0))"
  bot_note
  [[ $chk_fail -eq 0 ]] || exit 1
}

cmd_wings() {
  init_log; preflight_common wings
  head1 "Konfigurasi Wings"
  if [[ $ENABLE_SSL == ask ]]; then ENABLE_SSL=false; fi
  if [[ -z "$WINGS_PANEL_URL" && $HAVE_TTY == 1 ]]; then
    info "Isi data berikut dari Panel (Admin → Nodes → node → tab Configuration) atau kosongkan untuk konfigurasi manual nanti."
    prompt WINGS_PANEL_URL "URL Panel (mis. https://panel.domain.com), kosong = lewati" ""
    if [[ -n "$WINGS_PANEL_URL" ]]; then
      prompt WINGS_NODE_ID "ID Node" ""
      prompt WINGS_TOKEN "Application API key (ptla_...)" "" secret
    fi
    if [[ -z "$NODE_FQDN" ]] && confirm "Terbitkan SSL Let's Encrypt untuk FQDN node ini?" n; then
      prompt NODE_FQDN "FQDN node (harus sudah mengarah ke VPS ini)" ""; ENABLE_SSL=true
    fi
  fi
  local do_cfg=0
  if [[ -n "$WINGS_PANEL_URL" && -n "$WINGS_NODE_ID" && -n "$WINGS_TOKEN" ]]; then
    [[ $WINGS_NODE_ID =~ ^[0-9]+$ ]] || die "--node-id harus angka."
    [[ $WINGS_PANEL_URL =~ ^https?://[^[:space:]]+$ ]] || die "--panel-url harus diawali http:// atau https://"
    do_cfg=1
  fi
  local do_ssl=0
  if [[ -n "$NODE_FQDN" && ( $ENABLE_SSL == true ) ]]; then
    NODE_FQDN="${NODE_FQDN,,}"; [[ $NODE_FQDN =~ $HOST_RE ]] || die "FQDN node '$NODE_FQDN' tidak valid."
    if [[ -n "$(port_owner 80)" && "$(port_owner 80)" != "nginx" ]]; then warn "Port 80 terpakai, SSL node dilewati."
    else dns_matches "$NODE_FQDN" || true; do_ssl=1; fi
  fi
  STEP_TOTAL=3; STEP_NUM=0
  if [[ $do_cfg == 1 ]]; then STEP_TOTAL=$((STEP_TOTAL + 1)); fi
  if [[ $do_ssl == 1 ]]; then STEP_TOTAL=$((STEP_TOTAL + 1)); fi
  if [[ $HAVE_TTY == 1 ]]; then confirm "Mulai instalasi Wings sekarang?" y || { ERR_SHOWN=1; warn "Dibatalkan."; exit 0; }; fi
  head1 "Instalasi Wings berjalan  ${GRY}(log: $LOG_FILE)"
  local t0=$SECONDS
  run_step "Memasang Docker"                        step_docker
  run_step "Memasang Wings & service systemd"       step_wings_bin
  if [[ $do_ssl == 1 ]]; then run_step -s "Menerbitkan SSL untuk node ($NODE_FQDN)" step_node_ssl || true; fi
  if [[ $do_cfg == 1 ]]; then run_step -s "Mengonfigurasi Wings dari Panel" step_wings_configure || warn "wings configure gagal; cek URL/token/ID node dan pastikan Panel bisa dijangkau."; fi
  run_step -s "Menyalakan Wings"                    step_wings_start || warn "Wings belum bisa jalan; cek: journalctl -u wings -n 50"
  validate_wings
  echo
  printf '  %s%s┏━━ 🚀  WINGS TERPASANG  (%ss) ━━━━━━━━━━━━━━━━━━━━┓%s\n' "$BLD" "$GRN" "$((SECONDS - t0))" "$RST"
  if [[ -s /etc/pterodactyl/config.yml ]]; then
    printf '  %s┃%s  Wings sudah terkonfigurasi & berjalan.\n' "$GRN" "$RST"
  else
    printf '  %s┃%s  Langkah terakhir (manual):\n' "$GRN" "$RST"
    printf '  %s┃%s   1. Panel → Admin → Nodes → pilih node → tab Configuration\n' "$GRN" "$RST"
    printf '  %s┃%s   2. Klik "Generate Token", salin perintahnya, jalankan di VPS ini\n' "$GRN" "$RST"
    printf '  %s┃%s   3. systemctl enable --now wings\n' "$GRN" "$RST"
  fi
  printf '  %s┃%s  %sPort yang harus terbuka: 8080/tcp (Wings) dan 2022/tcp (SFTP) + port game%s\n' "$GRN" "$RST" "$GRY" "$RST"
  printf '  %s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%s\n\n' "$GRN" "$RST"
  [[ $chk_fail -eq 0 ]] || exit 1
}

cmd_full() {
  init_log; preflight_common panel; preflight_panel; gather_panel_config; gather_node_config
  local node_ssl=0
  if [[ $ENABLE_SSL == true && "$NODE_FQDN" != "$FQDN" ]]; then node_ssl=1; fi
  STEP_TOTAL=$(( $(panel_step_count) + 4 + node_ssl ))
  summary_box "$(printf '%-12s %s' 'Panel URL' "$APP_URL")" "$(printf '%-12s %s' 'Admin' "$ADMIN_USER <$ADMIN_EMAIL>")" \
    "$(printf '%-12s %s' 'SSL' "$ENABLE_SSL")" "$(printf '%-12s %s' 'Node' "$NODE_NAME @ $NODE_FQDN")" "$(printf '%-12s %s' 'Lokasi' "$LOC_SHORT ($LOC_LONG)")"
  if [[ $HAVE_TTY == 1 ]]; then confirm "Mulai instalasi Panel + Wings + Node?" y || { ERR_SHOWN=1; warn "Dibatalkan."; exit 0; }; fi
  head1 "Instalasi berjalan  ${GRY}(log: $LOG_FILE)"
  local t0=$SECONDS
  run_panel_steps
  run_step "Memasang Docker"                        step_docker
  run_step "Memasang Wings & service systemd"       step_wings_bin
  if [[ $node_ssl == 1 ]]; then run_step -s "Menerbitkan SSL untuk node ($NODE_FQDN)" step_node_ssl || true; fi
  run_step -s "Membuat Location & Node otomatis"    step_node_create || warn "Node gagal dibuat otomatis; buat manual di Panel → Admin → Nodes lalu konfigurasi Wings."
  run_step -s "Menyalakan Wings"                    step_wings_start || warn "Wings belum bisa jalan; cek: journalctl -u wings -n 50"
  validate_panel
  validate_wings
  write_creds
  panel_summary "$((SECONDS - t0))"
  if [[ -s "$NODE_STATE_FILE" ]]; then
    info "Node ID $(cat "$NODE_STATE_FILE") ($NODE_NAME) dibuat & Wings dijalankan."
    info "Tambah allocation (IP:port) di Panel → Admin → Nodes → ${NODE_NAME} → Allocation, lalu buat server."
  fi
  if [[ "$APP_URL" == https://* && ! -f "/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem" ]]; then
    warn "Panel HTTPS tetapi node tanpa SSL: browser memblokir console. Terbitkan SSL untuk ${NODE_FQDN} lalu ubah scheme node ke https."
  fi
  bot_note
  [[ $chk_fail -eq 0 ]] || exit 1
}

svc_dot() { if systemctl is-active --quiet "$1" 2>/dev/null; then printf '%s●%s aktif' "$GRN" "$RST"; else printf '%s●%s mati/tidak ada' "$RED" "$RST"; fi; }

cmd_status() {
  head1 "Status server"
  [[ -r /etc/os-release ]] && . /etc/os-release
  local ram disk pip
  ram="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"; disk="$(df -Pm / | awk 'NR==2 {print $4}')"
  pip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || echo '-')"
  printf '  %-18s %s\n' "OS" "${PRETTY_NAME:-?}"
  printf '  %-18s %s MB total • %s MB disk kosong\n' "Resource" "$ram" "$disk"
  printf '  %-18s %s\n' "IP publik" "$pip"
  head1 "Panel"
  if panel_installed; then
    local url ver
    url="$(grep -E '^APP_URL=' "$PTERO_DIR/.env" | cut -d= -f2- | tr -d '"')"
    ver="$(cd "$PTERO_DIR" && php artisan p:info 2>/dev/null | grep -iE 'panel version' | head -n1 | sed 's/^[[:space:]]*//' || true)"
    printf '  %-18s %s\n' "Terpasang" "ya ($PTERO_DIR)"
    printf '  %-18s %s\n' "URL" "$url"
    [[ -n "$ver" ]] && printf '  %-18s %s\n' "Versi" "$ver"
    local f; f="$(awk -F'[/:]+' '{print $2}' <<<"$url")"
    if [[ -f "/etc/letsencrypt/live/$f/fullchain.pem" ]]; then
      printf '  %-18s %s\n' "SSL berakhir" "$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$f/fullchain.pem" | cut -d= -f2)"
    fi
  else printf '  %-18s %s\n' "Terpasang" "belum"; fi
  local s; for s in nginx mariadb redis-server pteroq; do printf '  %-18s %s\n' "$s" "$(svc_dot "$s")"; done
  local fpm; fpm="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]+-fpm\.service$' | head -n1 || true)"
  [[ -n "$fpm" ]] && printf '  %-18s %s\n' "${fpm%.service}" "$(svc_dot "$fpm")"
  head1 "Wings"
  if wings_installed; then
    printf '  %-18s %s\n' "Terpasang" "ya"
    printf '  %-18s %s\n' "docker" "$(svc_dot docker)"
    printf '  %-18s %s\n' "wings" "$(svc_dot wings)"
    printf '  %-18s %s\n' "config.yml" "$([[ -s /etc/pterodactyl/config.yml ]] && echo ada || echo 'belum ada')"
  else printf '  %-18s %s\n' "Terpasang" "belum"; fi
  head1 "Port"
  local p o; for p in 80 443 8080 2022; do o="$(port_owner "$p")"; printf '  %-18s %s\n' "$p" "${o:--}"; done
  echo
}

cmd_admin() {
  panel_installed || die "Panel belum terpasang di $PTERO_DIR."
  init_log
  head1 "Tambah admin Panel"
  local email user first last pw gen=0
  prompt email "Email" "${ADMIN_EMAIL:-}"
  [[ $email =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Email tidak valid / kosong (pakai --email)."
  prompt user "Username" "admin2"
  [[ $user =~ ^[A-Za-z0-9._-]{1,191}$ ]] || die "Username tidak valid."
  first="Admin"; last="Rizzx"
  pw="$ADMIN_PASSWORD"
  if [[ -z "$pw" && $HAVE_TTY == 1 ]]; then prompt pw "Password (kosong = acak)" "" secret; fi
  if [[ -z "$pw" ]]; then pw="$(rand_str 20)"; gen=1; fi
  (( ${#pw} >= 8 )) || die "Password minimal 8 karakter."
  STEP_TOTAL=1
  ADMIN_EMAIL="$email"; ADMIN_USER="$user"; ADMIN_PASSWORD="$pw"
  run_step "Membuat admin '$user'" step_admin_extra
  summary_box "$(printf '%-10s %s' 'Username' "$user")" "$(printf '%-10s %s' 'Email' "$email")" "$(printf '%-10s %s' 'Password' "$pw")"
  [[ $gen == 1 ]] && warn "Simpan password ini, tidak ditampilkan lagi."
  return 0
}
step_admin_extra() {
  cd "$PTERO_DIR"
  php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" \
    --name-first="$ADMIN_FIRST" --name-last="$ADMIN_LAST" --password="$ADMIN_PASSWORD" --admin=1
  chown -R www-data:www-data "$PTERO_DIR/storage" 2>/dev/null || true
}

step_backup() {
  local dir="/root/rizzx-backup-$(date +%Y%m%d-%H%M%S)" dumper db
  mkdir -p "$dir"; chmod 700 "$dir"
  cp -a "$PTERO_DIR/.env" "$dir/panel.env"
  db="$(grep -E '^DB_DATABASE=' "$PTERO_DIR/.env" | cut -d= -f2- | tr -d '"')"
  dumper="$(command -v mariadb-dump || command -v mysqldump)"
  "$dumper" --single-transaction "${db:-$DB_NAME}" >"$dir/database.sql"
  echo "$dir" >/tmp/.rizzx-backup-dir
  echo "Backup: $dir"
}

step_update_panel() {
  cd "$PTERO_DIR"
  trap 'cd "$PTERO_DIR" && php artisan up >/dev/null 2>&1 || true' EXIT
  php artisan down
  dl "$(panel_tar_url)" /tmp/rizzx-panel.tar.gz
  tar -xzf /tmp/rizzx-panel.tar.gz -C "$PTERO_DIR"
  rm -f /tmp/rizzx-panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
  php artisan view:clear
  php artisan config:clear
  php artisan migrate --seed --force
  chown -R www-data:www-data "$PTERO_DIR"
  php artisan queue:restart
  php artisan up
  systemctl restart "php${PHP_VER}-fpm" pteroq.service
}

cmd_update() {
  panel_installed || die "Panel belum terpasang di $PTERO_DIR."
  init_log
  command -v php >/dev/null 2>&1 || die "PHP tidak ditemukan."
  PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  head1 "Update Panel"
  warn "Jika kamu memasang PROTECT dari bot V8, patch-nya tertimpa update; pasang ulang lewat bot setelahnya."
  if [[ $HAVE_TTY == 1 ]]; then confirm "Lanjut update Panel ke ${PANEL_VERSION}?" y || { ERR_SHOWN=1; warn "Dibatalkan."; exit 0; }; fi
  STEP_TOTAL=2
  run_step "Backup .env & database"        step_backup
  run_step "Update Panel (maintenance mode otomatis)" step_update_panel
  [[ -f /tmp/.rizzx-backup-dir ]] && info "Backup tersimpan di: $(cat /tmp/.rizzx-backup-dir)"
  rm -f /tmp/.rizzx-backup-dir
  ok "Update selesai."
  echo
}

menu() {
  banner
  local pst wst
  if panel_installed; then pst="${GRN}terpasang${RST}"; else pst="${GRY}belum${RST}"; fi
  if wings_installed; then wst="${GRN}terpasang${RST}"; else wst="${GRY}belum${RST}"; fi
  printf '  %sPanel:%s %s   %sWings:%s %s\n\n' "$GRY" "$RST" "$pst" "$GRY" "$RST" "$wst"
  printf '   %s1%s  🦖  Install Panel\n'                          "$CYN" "$RST"
  printf '   %s2%s  🪽  Install Wings (VPS node)\n'                "$CYN" "$RST"
  printf '   %s3%s  🚀  Full: Panel + Wings + Node otomatis\n'     "$CYN" "$RST"
  printf '   %s4%s  📊  Status server\n'                           "$CYN" "$RST"
  printf '   %s5%s  👤  Tambah admin Panel\n'                      "$CYN" "$RST"
  printf '   %s6%s  ⬆️   Update Panel\n'                           "$CYN" "$RST"
  printf '   %s0%s  ✖   Keluar\n\n'                               "$CYN" "$RST"
  local c; prompt c "Pilih menu" "1"
  case "$c" in
    1) CMD=panel ;; 2) CMD=wings ;; 3) CMD=full ;; 4) CMD=status ;; 5) CMD=admin ;; 6) CMD=update ;;
    0|q|Q) ERR_SHOWN=1; exit 0 ;;
    *) die "Pilihan '$c' tidak valid." ;;
  esac
  echo
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════
need_root
if [[ -z "$CMD" || "$CMD" == "menu" ]]; then
  if [[ $HAVE_TTY == 1 ]]; then menu
  else banner; usage; die "Tanpa terminal interaktif, sebutkan perintah: panel | wings | full | status | admin | update"; fi
else
  banner
fi

case "$CMD" in
  panel)  cmd_panel ;;
  wings)  cmd_wings ;;
  full)   cmd_full ;;
  status) cmd_status ;;
  admin)  cmd_admin ;;
  update) cmd_update ;;
esac
