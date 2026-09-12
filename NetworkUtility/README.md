# 🌐 NetworkUtility — BBRv3 Benchmark, SQM, Split-DNS & Network Tools

Kumpulan utilitas, skrip otomasi dispatcher, hook VPN, dan konfigurasi jaringan untuk CachyOS Linux:
- Menguji performa throughput jarak jauh (*High Bandwidth-Delay Product*) dan ekspansi *TCP Window Scaling* (32 MB buffer).
- Membaca telemetri *state machine* kernel Linux **TCP BBRv3**.
- Otomasi **CAKE Smart Queue Management (SQM)** per SSID Wi-Fi untuk mengeliminasi *bufferbloat*.
- Mengatasi problem rute bawaan DHCP korporat (**RFC 3442 Option 121**) agar koneksi LAN/Wi-Fi tidak kehilangan *default gateway*.
- Drop-in konfigurasi **systemd-resolved** dengan **Cloudflare** (ultra-fast, bebas drop EDNS0) + **Quad9** (malware blocking) via UDP 53 stabil tanpa *timeout* firewall kantor.
- Automasi **Split-DNS Telkom** via VPNC post-connect hook untuk OpenConnect / GlobalProtect.

---

## 📁 Daftar Skrip & Konfigurasi

### 1. `01-dhcp-default-route.sh`
NetworkManager dispatcher script (`/etc/NetworkManager/dispatcher.d/01-dhcp-default-route.sh`) untuk memperbaiki kehilangan *default route* akibat anomali DHCP RFC 3442 dan melakukan *DNS sanitization* pada jaringan kantor `10.x.x.x`.

#### 🚨 Masalah yang Diatasi:
1. **RFC 3442 Classless Static Route Bug**: Server DHCP korporat (misal kantor Telkom) sering kali mengirimkan rute statis spesifik via Option 121 tanpa menyertakan rute default (`0.0.0.0/0`). Berdasarkan standar RFC 3442, NetworkManager secara otomatis mengabaikan Option 3 (Router/Gateway), mengakibatkan antarmuka LAN/Wi-Fi tidak memiliki default route sehingga koneksi internet publik mati total.
2. **DNS Choke / Latensi Lambat di Jaringan Kantor**: DHCP kantor sering kali menyuntikkan DNS resolver lokal (`10.x.x.x`) yang membatasi kecepatan atau memblokir akses ke layanan pengembangan publik.
3. **Roaming Stale Sockets & Blackhole Hang**: Saat berpindah jaringan (misal dari tethering/Wi-Fi rumah ke Wi-Fi kantor), koneksi TCP `language_server` (Antigravity IDE) masih menggantung pada IP lama atau mencoba menghubungi rentang `172.217.0.0/16` yang di-blackhole oleh router korporat. Hal ini membuat aplikasi stuck berstatus "Working..." tanpa henti.

#### ⚙️ Solusi & Cara Kerja:
- **Auto-Restore Default Route**: Pada trigger `up`, `dhcp4-change`, atau `reapply`, skrip memeriksa apakah ada *default route* pada interface. Jika kosong, skrip mengekstrak IP router dari environment `DHCP4_ROUTERS` atau `nmcli` dan memasang rute default secara dinamis (`ip route replace default via $ROUTER dev $IFACE metric $METRIC`).
- **DNS Sanitization**: Jika antarmuka mendeteksi subnet `10.x.x.x`, DNS pada antarmuka tersebut otomatis diarahkan ke Cloudflare (`1.1.1.1`) dan Quad9 (`9.9.9.9`) melalui `resolvectl dns`, sehingga internet umum (browsing, Antigravity, git, OneDrive) dapat menikmati kecepatan penuh gigabit LAN tanpa tercekik latensi. Domain intranet kantor tetap ditangani oleh antarmuka VPN `tun0`.
- **Fast Reconnect & Blackhole Socket Reset**: Skrip memicu pembersihan paksa soket TCP lama yang tertahan ke pool Google APIs (`ss -K 'dst 172.217.0.0/16'` dan `ss -K 'dst 142.250.0.0/15'`) agar koneksi langsung terputus dan terbentuk ulang seketika menggunakan IP baru tanpa menunggu timeout TCP berdurasi puluhan detik.

#### 🛠️ Instalasi:
```bash
sudo cp NetworkUtility/01-dhcp-default-route.sh /etc/NetworkManager/dispatcher.d/
sudo chmod +x /etc/NetworkManager/dispatcher.d/01-dhcp-default-route.sh
```

---

### 2. Google APIs Edge VIPs (`/etc/hosts`)

#### 🚨 Masalah yang Diatasi:
Router / firewall kantor pada jaringan `10.131.40.1` (`Team SO-FF PAMASUKA`) mengalami salah konfigurasi rute (*bogons/null-route*) yang memblokir/me-drop seluruh rentang alamat IP publik `172.217.0.0/16`. Secara default, DNS global mengarahkan endpoint Google APIs (`daily-cloudcode-pa.googleapis.com`, `generativelanguage.googleapis.com`, `play.googleapis.com`) ke pool Singapura `172.217.112.4` – `172.217.119.4`. Akibatnya, Antigravity AI IDE tidak dapat mengirimkan prompt atau menerima respons (hang total), sementara web browser biasa lancar karena mengakses domain Google via rentang `216.x.x.x` atau `74.x.x.x`.

#### ⚙️ Solusi:
Tambahkan pemetaan IP Anycast Google Frontend global (`142.250.4.106`) langsung pada `/etc/hosts` agar tidak lagi mengarah ke rentang `172.217.0.0/16`:
```hosts
# Google APIs Edge VIPs (Bypass corporate 172.217.x.x blackhole on Team SO-FF PAMASUKA)
142.250.4.106 daily-cloudcode-pa.googleapis.com
142.250.4.106 generativelanguage.googleapis.com
142.250.4.106 play.googleapis.com
```
Alamat `142.250.4.106` terbukti lolos dari blokir router korporat, memiliki latensi rendah (~200 ms), dan menyajikan sertifikat SSL wildcard valid `*.googleapis.com`.

---

### 3. `split-dns.sh`
VPNC post-connect hook script (`/etc/vpnc/post-connect.d/split-dns.sh`) untuk integrasi OpenConnect / GlobalProtect dengan `systemd-resolved`.

#### 🚨 Masalah yang Diatasi:
Saat terhubung ke VPN Telkom GlobalProtect, gateway VPN tidak selalu mengirimkan parameter *search/routing domain* (`CISCO_DEF_DOMAIN`). Tanpa routing domain (domain ber-prefix `~`), `systemd-resolved` melakukan query paralel ke DNS Wi-Fi/LAN publik dan DNS VPN. Resolver publik menjawab lebih cepat dengan status *NXDOMAIN / NODATA*, memicu *negative answer caching* yang mengakibatkan aplikasi web intranet (seperti KARINA, UNM2000, iBooster, OSS Incident) gagal diakses dengan error `NS_ERROR_UNKNOWN_HOST`.

#### ⚙️ Solusi & Cara Kerja:
Skrip dieksekusi otomatis oleh `vpnc-script` saat link VPN aktif (`post-connect`). Skrip ini mendaftarkan routing domain korporat secara eksklusif ke interface virtual VPN (`$TUNDEV` / `tun0`) dan mematikan DNSSEC link lokal:
```bash
/usr/bin/resolvectl domain "$TUNDEV" "~telkom.co.id" "~telkom.net" "~telkomakses.co.id" "~telkom.center"
/usr/bin/resolvectl dnssec "$TUNDEV" no
```

#### 🛠️ Instalasi:
```bash
sudo mkdir -p /etc/vpnc/post-connect.d
sudo cp NetworkUtility/split-dns.sh /etc/vpnc/post-connect.d/
sudo chmod +x /etc/vpnc/post-connect.d/split-dns.sh
```

---

### 4. `dns.conf`
Drop-in configuration file untuk `systemd-resolved` (`/etc/systemd/resolved.conf.d/dns.conf`).

#### ⚙️ Konfigurasi & Fitur:
- **Primary DNS**: **Cloudflare** (`1.1.1.1`, `2606:4700:4700::1111`) — Resolusi DNS global berkecepatan ultra-tinggi (19 ms), andal, dan terbukti tidak di-drop oleh inspeksi EDNS0 firewall korporat.
- **Secondary DNS**: **Quad9** (`9.9.9.9`, `2620:fe::fe`) — Proteksi keamanan aktif terhadap malware, phishing, dan infrastruktur C2 berbahaya secara langsung di level DNS.
- **Fallback DNS**: Cloudflare Secondary (`1.0.0.1`, `2606:4700:4700::1001`) & Quad9 Secondary (`149.112.112.112`, `2620:fe::9`).
- **Global Routing Domain**: `Domains=~.` — Menjadikan Cloudflare/Quad9 sebagai *default routing target* untuk semua domain internet umum, mencegah kebocoran DNS saat split-tunneling VPN berjalan.
- **DNSOverTLS=no**: **Alasan Kritis** — Firewall korporat/kantor Telkom memblokir/me-drop traffic port 853 (DoT). Mengaktifkan DoT menyebabkan query DNS mengalami *TCP connection timeout* selama 10–12 detik per request sebelum fallback. Dengan UDP port 53 standar, latensi DNS instan (<5 ms lokal cache), dan keamanan tetap terjaga melalui filter malware Quad9.
- **Optimasi Tambahan**: `LLMNR=no` (menghindari broadcast noise), `Cache=yes`, `StaleRetentionSec=3600` (melayani cache kedaluwarsa sementara saat koneksi jaringan transisi).

#### 🛠️ Instalasi:
```bash
sudo cp NetworkUtility/dns.conf /etc/systemd/resolved.conf.d/dns.conf
sudo systemctl restart systemd-resolved
```

---

### 5. `99-wifi-cake-sqm.sh`
NetworkManager dispatcher script (`/etc/NetworkManager/dispatcher.d/99-wifi-cake-sqm.sh`) untuk menerapkan antrean **CAKE SQM (Common Applications Kept Enhanced)** secara otomatis dan dinamis berdasarkan SSID Wi-Fi yang sedang terhubung.

#### ⚙️ Profil & Fitur:
- **Bandwidth Profiling per SSID**:
  - `SemangatPagi!-Game`: Up 40 Mbit (Down target 143 Mbit)
  - `POCO F6` / Tethering: Up 30 Mbit (Down target 50 Mbit)
  - `Lokale Select MT Haryono`: Up 8 Mbit (Down target 8 Mbit)
  - `Lokale Select Sudirman`: Up 40 Mbit (Down target 70 Mbit)
  - `ROCVI`: Up 25 Mbit (Down target 95 Mbit)
  - `@28FINEST`: Up 6 Mbit (Down target 10 Mbit)
  - `Team SO-FF PAMASUKA`: Mode CAKE *unlimited* (adaptif)
  - `Default / SSID Lain`: Mode CAKE *unlimited* (tanpa pembatasan bandwidth)
- **Anti-Bufferbloat**: Menggunakan algoritma `diffserv3` (prioritas 3-tingkat: bulk, best effort, voice/interactive) dan `ack-filter` untuk mengompresi ACK packet pada link asimetris, mencegah latensi melonjak saat upload penuh.
- **Overhead Framing**: Menyesuaikan `overhead 44 mpu 64` untuk encapsulasi frame 802.11 Wi-Fi.

#### 🛠️ Instalasi:
```bash
sudo cp NetworkUtility/99-wifi-cake-sqm.sh /etc/NetworkManager/dispatcher.d/
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-wifi-cake-sqm.sh
```

---

### 6. `bbr3_benchmark.fish`
Skrip native Fish shell untuk menjalankan *single-stream* TCP download jarak jauh ke server benua Eropa (default: Hetzner Jerman) sekaligus mengambil sampling telemetri soket TCP kernel (`ss -tin`) secara real-time.

#### 🚀 Cara Penggunaan:
```fish
# Jalankan dengan server default (Hetzner 1GB)
fish NetworkUtility/bbr3_benchmark.fish

# Atau tentukan URL target kustom
fish NetworkUtility/bbr3_benchmark.fish "https://mirror.nl.leaseweb.net/speedtest/1000mb.bin"
```

#### 📊 Metrik yang Diamati:
- `bw:...bps` : Estimasi *bottleneck bandwidth* aktual yang diukur oleh BBRv3.
- `delivery_rate:...bps` : Laju pengiriman paket data yang berhasil diakui (*ACKed*).
- `send ...bps` : Kecepatan *instantaneous packet sending*.
- `pacing_rate ...bps` : Laju *pacing* transmisi paket oleh kernel.
- `snd_wnd:...` & `rcv_wnd:...` : Ukuran jendela transmisi (*Window Scaling* buffer 32 MB).
- `minrtt:...` : Round Trip Time minimum untuk mendeteksi ada tidaknya *bufferbloat*.
- `pacing_gain` & `cwnd_gain` : Pengali *pacing* dan *congestion window* sesuai fase state BBRv3.

---

### 7. `bbr3_inspect.py`
Skrip Python untuk membaca struktur internal `tcp_bbr_info` langsung dari kernel Linux menggunakan socket option `TCP_CC_INFO` (`getsockopt`).

#### 🚀 Cara Penggunaan:
```bash
python3 NetworkUtility/bbr3_inspect.py
# Atau dengan host/port kustom:
python3 NetworkUtility/bbr3_inspect.py 9.9.9.9 443
```

#### 🔍 Informasi yang Ditampilkan:
- `bbr_version` : Versi algoritma BBR di kernel (BBRv3 = `3`).
- `bbr_phase` : Fase state machine BBRv3 aktif (`STARTUP`, `DRAIN`, `PROBE_RTT`, `PROBE_BW_UP`, `PROBE_BW_DOWN`, `PROBE_BW_CRUISE`, `PROBE_BW_REFILL`).
- `Pacing Gain` & `Cwnd Gain` : Nilai desimal *gain multiplier*.
