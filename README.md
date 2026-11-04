# 🦖 RIZZX Pterodactyl All-in-One Installer

Installer satu perintah untuk **Pterodactyl Panel**, **Wings**, dan **Node otomatis**.
Bisa dipakai manual tanpa bot Telegram, dan tetap kompatibel dengan bot RIZZX V8.

## ⚡ Install cepat

Jalankan sebagai **root** di VPS bersih:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/skyyror/rizzx-installer/main/install-panel.sh)
```

Perintah di atas membuka **menu interaktif**. Mau langsung ke perintah tertentu:

```bash
# Panel saja
bash <(curl -fsSL https://raw.githubusercontent.com/skyyror/rizzx-installer/main/install-panel.sh) panel --fqdn panel.domain.com --ssl --yes

# Panel + Wings + Node otomatis (satu VPS)
bash <(curl -fsSL https://raw.githubusercontent.com/skyyror/rizzx-installer/main/install-panel.sh) full --fqdn panel.domain.com --ssl --yes

# Wings saja (VPS node terpisah)
bash <(curl -fsSL https://raw.githubusercontent.com/skyyror/rizzx-installer/main/install-panel.sh) wings --panel-url https://panel.domain.com --node-id 1 --token ptla_xxx
```

> Ganti `USERNAME` dengan username GitHub kamu dan `panel.domain.com` dengan domain Panel.
> Domain harus sudah diarahkan (record A) ke IP VPS. Kalau pakai Cloudflare, set **DNS only** (awan abu-abu).

## 📋 Perintah

| Perintah | Fungsi |
|----------|--------|
| *(kosong)* | Menu interaktif |
| `panel` | Install Panel (Nginx, PHP 8.3, MariaDB, Redis, SSL opsional) |
| `wings` | Install Docker + Wings |
| `full` | Panel + Wings + Location & Node otomatis di satu VPS |
| `status` | Cek Panel, Wings, service, port, dan masa berlaku SSL |
| `admin` | Tambah akun admin Panel |
| `update` | Update Panel ke rilis terbaru (backup otomatis) |

## 🔧 Opsi

| Opsi | Keterangan |
|------|------------|
| `--fqdn <domain>` | Domain Panel (atau IP) |
| `--email <email>` | Email admin (default `admin@<domain-utama>`) |
| `--password <pw>` | Password admin (default acak) |
| `--timezone <tz>` | Default `Asia/Jakarta` |
| `--ssl` / `--no-ssl` | Let's Encrypt on/off |
| `--version <vX.Y.Z>` | Versi Panel (default `latest`) |
| `--api-key` | Buat Application API key (`ptla_`) |
| `--yes`, `-y` | Mode tanpa pertanyaan |
| `--force-os` | Lewati cek OS (risiko ditanggung sendiri) |
| `--node-fqdn` | FQDN node (default = FQDN Panel) |
| `--node-name` | Nama node (default `Node-RIZZX`) |
| `--node-ram <MB>` | RAM node (default total RAM - 1024) |
| `--location <KODE>` | Kode lokasi (default `ID`), nama lewat `--location-name` |
| `--panel-url`, `--node-id`, `--token` | Konfigurasi Wings dari Panel jarak jauh |

Bantuan lengkap: `bash install-panel.sh --help`

## ✅ Persyaratan

- OS: **Ubuntu 22.04 / 24.04** atau **Debian 11 / 12**
- Akses **root**, arsitektur `x86_64` atau `aarch64`
- RAM minimal 1 GB (disarankan 2 GB), disk kosong minimal 3 GB (disarankan > 5 GB)
- Virtualisasi **KVM/dedicated** untuk Wings (OpenVZ tidak didukung)
- Port **80/443** bebas saat instalasi Panel

## 📦 Hasil instalasi

- Panel di `/var/www/pterodactyl`
- Admin utama: username `admin` (ID 1)
- Service `pteroq` dan cron scheduler aktif
- Vhost Nginx `/etc/nginx/sites-enabled/pterodactyl.conf`
- Kredensial disimpan di `/root/rizzx-panel-credentials.txt` (chmod 600)
- Log instalasi di `/var/log/rizzx-panel-install.log`

## 🛡️ Keamanan

- Script **menolak** berjalan kalau Panel atau database `panel` sudah ada, supaya data lama tidak tertimpa.
- Tidak ada yang dihapus otomatis saat instalasi gagal.
- Baca script sebelum menjalankannya, dan pakai URL **tag/release** (contoh `.../v2.0.0/install-panel.sh`) agar versinya tetap.

Verifikasi hash file:

```bash
curl -fsSL https://raw.githubusercontent.com/USERNAME/rizzx-installer/main/install-panel.sh | sha256sum
```

## 🤖 Integrasi bot RIZZX V8

- Admin `admin` (ID 1) cocok dengan `PROTECT_ROOT_ADMIN_ID=1`.
- Isi `PTERODACTYL_APPLICATION_API_KEY` di `.env` bot dengan key dari `--api-key`, atau kosongkan agar bot membuat sendiri.
- Jangan jalankan `/installpanel` bot di VPS yang sudah dipasang script ini.
- Setelah `update`, patch PROTECT bot tertimpa; pasang ulang lewat bot.

## ❓ Troubleshooting

| Masalah | Solusi |
|---------|--------|
| SSL gagal terbit | Pastikan domain mengarah ke IP VPS dan port 80 terbuka, lalu jalankan ulang. Panel tetap jalan via HTTP. |
| Port 80/443 dipakai | Hentikan Apache/web server lain: `systemctl disable --now apache2` |
| Wings tidak jalan | Cek `journalctl -u wings -n 50` dan pastikan `/etc/pterodactyl/config.yml` ada |
| Langkah gagal | Lihat 20 baris log yang ditampilkan, atau `/var/log/rizzx-panel-install.log` |

## 📜 Lisensi

MIT. Silakan pakai dan modifikasi.
