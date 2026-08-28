# 🌐 NetworkUtility — BBRv3 Benchmark, SQM & Network Tools

Kumpulan utilitas, skrip diagnostik, dan konfigurasi jaringan untuk menguji performa throughput jarak jauh (*High Bandwidth-Delay Product*), memvalidasi ekspansi *TCP Window Scaling* (32 MB buffer), membaca telemetri *state machine* kernel Linux **TCP BBRv3**, otomasi **CAKE Smart Queue Management (SQM)** per SSID Wi-Fi, serta drop-in konfigurasi DNS resolver sistem.

---

## 📁 Daftar Skrip & Konfigurasi

### 1. `bbr3_benchmark.fish`
Skrip native Fish shell untuk menjalankan *single-stream* TCP download jarak jauh ke server benua Eropa (default: Hetzner Jerman) sekaligus mengambil sampling telemetri soket TCP kernel (`ss -tin`) secara real-time.

#### 🚀 Cara Penggunaan:
```fish
# Jalankan dengan server default (Hetzner 1GB)
fish bbr3_benchmark.fish

# Atau tentukan URL target kustom
fish bbr3_benchmark.fish "https://mirror.nl.leaseweb.net/speedtest/1000mb.bin"
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

### 2. `bbr3_inspect.py`
Skrip Python untuk membaca struktur internal `tcp_bbr_info` langsung dari kernel Linux menggunakan socket option `TCP_CC_INFO` (`getsockopt`).

#### 🚀 Cara Penggunaan:
```bash
python3 bbr3_inspect.py
# Atau dengan host/port kustom:
python3 bbr3_inspect.py 1.1.1.1 443
```

#### 🔍 Informasi yang Ditampilkan:
- `bbr_version` : Versi algoritma BBR di kernel (BBRv3 = `3`).
- `bbr_phase` : Fase state machine BBRv3 aktif (`STARTUP`, `DRAIN`, `PROBE_RTT`, `PROBE_BW_UP`, `PROBE_BW_DOWN`, `PROBE_BW_CRUISE`, `PROBE_BW_REFILL`).
- `Pacing Gain` & `Cwnd Gain` : Nilai desimal *gain multiplier*.

---

### 3. `99-wifi-cake-sqm.sh`
NetworkManager dispatcher script (`/etc/NetworkManager/dispatcher.d/99-wifi-cake-sqm.sh`) untuk menerapkan konfigurasi antrean **CAKE SQM** secara otomatis dan dinamis berdasarkan SSID Wi-Fi yang sedang terhubung.

#### ⚙️ Profil & Fitur:
- **Bandwidth Profiling**: Menerapkan batas *uplink bandwidth* yang disesuaikan dengan kapasitas jaringan Wi-Fi/tethering (misalnya 41 Mbit untuk hotspot gaming, 30 Mbit untuk HP tethering, 50 Mbit untuk kafe/lokal, dan mode *unlimited* untuk SSID umum).
- **Anti-Bufferbloat**: Menggunakan `diffserv3` (3-tier prioritization) dan `ack-filter` untuk mengoptimalkan latensi game, Moonlight stream, dan voice/video calls saat jaringan sedang berada di bawah beban traffic tinggi.
- **Overhead Framing**: Menyesuaikan `overhead 44 mpu 64` untuk encapsulasi frame 802.11 Wi-Fi.

---

### 4. `dns.conf`
Drop-in configuration file untuk `systemd-resolved` (`/etc/systemd/resolved.conf.d/dns.conf`).
- **Primary DNS**: Cloudflare DNS-over-TLS (`1.1.1.1`, `2606:4700:4700::1111`).
- **Secondary / Fallback**: Google DNS (`8.8.8.8`, `2001:4860:4860::8888`).
- **Routing Domain**: `Domains=~.` (Catch-all global routing domain untuk mencegah leak DNS publik saat VPN split-tunnel aktif).
- **DNS-over-TLS**: `opportunistic`.
