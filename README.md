# Laporan Pengujian Performa & Responsivitas CachyOS

Laporan ini mendokumentasikan hasil pengujian komprehensif atas *stress-test*, latensi sistem, serta reliabilitas jaringan pada instalasi Linux-CachyOS. Pengujian ini bertujuan untuk memvalidasi apakah kombinasi parameter Kernel, *sysctl*, *scheduler* dinamis (**MuQSS Scheduler**), *patch* manajemen memori (lru_marie), dan optimisasi *hardened networking stack* Bottleneck Bandwidth and Round-trip propagation time (BBR) mampu untuk mempertahankan tingkat responsivitas sistem tertinggi, baik di bawah tekanan komputasi, memori, I/O disk, maupun utilitas *bandwidth* jaringan secara maksimal dengan tetap mempertahankan efisiensi daya.

---

## 💻 Spesifikasi Sistem
- **Sistem Operasi**: Linux CachyOS
- **Versi Kernel**: `7.2.0-ck1-1zen` (Custom Zen/CK Kernel w/ MuQSS & lru_marie)
- **Prosesor (CPU)**: AMD Ryzen 7 8845HS w/ Radeon 780M Graphics (8 Cores / 16 Threads)
- **Memori (RAM)**: 19 GiB
- **Swap / zRAM**: 19 GiB
- **Penyimpanan (Disk)**: KINGSTON OM8PGP4512N-A0 (476.9G NVMe SSD)

---

## ⚙️ Konfigurasi Sistem Terapan
Sistem dikonfigurasi secara spesifik untuk mengejar performa tingkat tinggi (High-Performance/Gaming/Low-Latency Setup).

### 1. Boot Parameters (GRUB/Kernel)
- `mitigations=off`: Mematikan mitigasi *hardware vulnerability* (Spectre/Meltdown) demi performa CPU mentah.
- `threadirqs`: Interupsi ditangani sebagai *thread* mandiri (karakteristik *preempt/low-latency*) agar proses berat tidak memblokir sinyal interupsi perangkat seperti *mouse* dan *keyboard*.
- `cpuidle.governor=teo`: Memilih keseimbangan optimal antara latensi *wake-up* CPU dan konsumsi daya.
- `zswap.enabled=0`: Menonaktifkan zswap agar *kernel* murni menggunakan alokasi penuh zRAM.
- `split_lock_detect=off` & `transparent_hugepage=madvise`: Pengaturan anti-*stutter* dan pencegahan fragmentasi untuk aplikasi dan *game* berat.

### 2. Parameter Sysctl (Memori & Jaringan)
- **I/O & Cache Management**:
  - `vm.dirty_bytes = 268435456` (256 MB)
  - `vm.dirty_background_bytes = 67108864` (64 MB)
  *(Membatasi buffer kotor absolut untuk mencegah stall/freeze I/O parah saat proses copy data raksasa ke NVMe).*
- **Swap Management (Untuk zRAM)**:
  - `vm.swappiness = 1`
  - `vm.page-cluster = 0`
- **Networking (TCP BBR)**:
  - `net.ipv4.tcp_congestion_control = bbr`
  - `net.ipv4.tcp_fastopen = 3`
  - Batas *buffer* `tcp_rmem` & `tcp_wmem` hingga 32MB.

### 3. Cgroups & Layanan Reclaim
- **lru_marie**: Sebuah inovasi *kernel patch* untuk manajemen memori (khususnya *reclaim/swap*) yang dikembangkan oleh [firelzrd](https://github.com/firelzrd/lru_marie). *Patch* ini secara efisien mendeteksi dan mengevakuasi memori di bawah tekanan (*memory pressure*), menjadikannya sangat tangguh menghadapi risiko sistem *hang/OOM* saat digunakan bersama konfigurasi *swap/zRAM* pada Linux.
- **Cgroups v2 (Unified)**: Aktif secara penuh.
- **systemd-oomd**: `Disabled / Inactive`. Hal ini disengaja agar *userspace OOM killer* tidak mengganggu algoritma canggih dari *patch* `lru_marie` di level *kernel*.

### 4. Scheduler (Penjadwal CPU)
- **MuQSS (Multiple Queue Skiplist Scheduler)**: *Custom CPU scheduler* karya Con Kolivas yang menggantikan CFS/EEVDF bawaan kernel. MuQSS mengimplementasikan antrean terisolasi berbasis struktur data *skiplist* per-CPU runqueue/cache domain dengan mekanisme *Earliest Deadline First (EDF) Virtual Deadline* berbasis `kernel.rr_interval = 6 ms`. Arsitektur ini memangkas habis *global lock contention*, meminimalkan *scheduling jitter*, serta menjamin latensi eksekusi instan dan deterministik untuk beban kerja interaktif (UI/UX, gaming, audio) tanpa mengorbankan *throughput* komputasi.

---

## 📊 Hasil Pengujian (*Stress-Test*)

Pengujian dilakukan dalam kondisi sistem sedang aktif digunakan (skenario dunia nyata dengan berbagai aplikasi berjalan di latar belakang).

### Fase 1: Uji Responsivitas Penjadwal (CPU Latency)
**Metodologi:** 
Membebani seluruh 16 *thread* CPU AMD Ryzen 7 8845HS hingga 100% menggunakan `stress-ng --matrix 0` selama 15 detik, sekaligus mengukur latensi interupsi sistem (*OS scheduling delay / wake-up jitter*) secara bersamaan menggunakan `cyclictest` pada mode *real-time* (`SCHED_FIFO` prio 90, memori terkunci via `mlockall`, interval $1\text{ ms} / 1000\ \mu\text{s}$ terdistribusi per core CPU `--smp`).

**Hasil Observasi:**
- **Rata-rata Latensi (*Average*):** Sangat impresif, berada di angka konsisten **$4\ \mu\text{s}$ hingga $5\ \mu\text{s}$ (~0.004 ms - 0.005 ms)** merata di seluruh 16 *threads*. Pergantian tugas (*context switching*) ditangani hampir secara instan (*near-zero overhead*).
- **Latensi Maksimal (*Max Jitter / Peak Spike*):** Mayoritas *thread* konsisten bertahan di bawah **$80\ \mu\text{s}$ ($0.08\text{ ms}$)**. Lonjakan puncak latensi terburuk (*worst-case spike*) hanya menyentuh batas **$177\ \mu\text{s}$ ($0.177\text{ ms}$)** di bawah beban matriks 100%.
- **Latensi Minimal (*Min*):** Konsisten di angka **$1\ \mu\text{s}$**.
- **Pengalaman Interaktif:** Pergerakan kursor tetikus (*mouse*), perpindahan *window*, serta animasi Wayland (`kwin_wayland`) tetap sangat responsif, mulus, dan sama sekali tidak ada tanda-tanda *stutter* maupun *freeze*.

#### ⚖️ Tabel Komparasi Latensi Penjadwal: MuQSS vs Infinity Scheduler (v4)

| Metrik Pengujian | Infinity Scheduler (v4) | MuQSS Scheduler (`7.2.0-ck1-1zen`) | Selisih / Keunggulan MuQSS |
| :--- | :--- | :--- | :--- |
| **Rata-rata Latensi (*Average*)** | $45\ \mu\text{s} - 57\ \mu\text{s}$ | **$4\ \mu\text{s} - 5\ \mu\text{s}$** | **$\approx 10\times$ Lebih Cepat** |
| **Puncak Latensi (*Peak Max Spike*)** | $\sim 4200\ \mu\text{s}$ ($4.2\text{ ms}$) | **$177\ \mu\text{s}$ ($0.177\text{ ms}$)** | **$\approx 23\times$ Lebih Stabil / Rendah** |
| **Mayoritas Latensi Maksimal** | $< 2000\ \mu\text{s}$ ($< 2\text{ ms}$) | **$< 89\ \mu\text{s}$ ($< 0.09\text{ ms}$)** | **Jauh lebih deterministik** |
| **Beban Pengujian** | 100% `stress-ng --matrix 0` | 100% `stress-ng --matrix 0` | Beban identik (16 Cores/Threads) |

**Kesimpulan Fase 1:**
Keunggulan performa MuQSS didukung oleh kombinasi faktor arsitektural dan parameter kernel:
1. **Struktur Data Skiplist per-CPU Runqueue**: MuQSS (*Multiple Queue Skiplist Scheduler*) menggunakan antrean *skiplist* terisolasi per-core/cache domain. Ini memangkas habis *lock contention* global yang biasa terjadi saat seluruh 16 *threads* dibebani serentak.
2. **Virtual Deadline (EDF Mechanism)**: Dengan `kernel.rr_interval = 6 ms`, MuQSS secara deterministik menghitung batas waktu eksekusi task interaktif dan *real-time* (`SCHED_FIFO`). Ketika ada *event* interupsi sistem atau input kursor/Wayland, task langsung disisipkan di posisi terdepan antrean tanpa terhalang kalkulasi *fair-share* dinamis yang berat.
3. **Sinergi Kernel Zen + `threadirqs` + PREEMPT**: Interupsi hardware dialihkan ke *threaded IRQ* berprioritas tinggi. Beban kalkulasi matriks pada *userspace* sama sekali tidak mampu menahan laju eksekusi *timer wake-up* kernel.
4. **Cache Locality AMD Zen 4**: Seluruh 8 Core / 16 Thread pada Ryzen 7 8845HS berada dalam satu CCX monolitik (Unified 16 MiB L3 Cache), memaksimalkan efisiensi saat MuQSS melakukan migrasi task cepat antar-thread.

---

### Fase 2: Uji Memori & I/O Stall (lru_marie & dirty_bytes)
**Metodologi:**
Dijalankan secara bersamaan:
1. `fio` menulis *file* sekuensial sebesar 2 GB dengan *engine libaio* dan `end_fsync=1` untuk membanjiri antrean disk I/O.
2. `stress-ng --vm 2 --vm-bytes 85%` mengalokasikan 1.42 GB RAM secara paksa selama 20 detik saat memori sudah sebagian besar terisi oleh aplikasi (*browser*, dll). Ini bertujuan untuk memicu *memory pressure* dan *page reclaim*.

**Hasil Observasi:**
- **I/O Disk (NVMe):** `fio` mencapai kecepatan penulisan di angka **5.550 MiB/s**. Lebih impresif lagi, *latency* penyelesaian (*completion latency/clat*) saat antrean data diflushing ke NVMe hanya berkisar **~10 milidetik**. Tidak ada indikasi *I/O Cliff* atau sistem tersendat.
- **Memory Reclaim (`lru_marie`):** `stress-ng` sukses berjalan penuh (*Passed: 2, Failed: 0*) tanpa gangguan. Aplikasi pengguna yang sedang terbuka (mis. *browser*) tidak mengalami *crash* atau tertutup paksa (*OOM Killed*).

**Kesimpulan Fase 2:** Kombinasi `vm.dirty_bytes=256MB` secara konkrit mampu menyetabilkan arus *writeback* disk kecepatan tinggi. Di saat yang sama, **patch lru_marie** membuktikan keunggulannya dalam mendeteksi dan melakukan evakuasi halaman *cache/swap* secara efisien ke zRAM tanpa menyebabkan Linux *hang* atau panik (kernel OOM).

---

### Fase 3: Uji Throughput & Stabilitas Jaringan (BBR)
**Metodologi:**
Melakukan pengujian *real-world throughput* jarak jauh via protokol TCP tunggal ke server benua Eropa, dipadukan dengan pemantauan parameter *socket* aktif secara *real-time* menggunakan utilitas `ss`.

**Hasil Observasi:**
- **Sustained Throughput:** Kecepatan transfer TCP jarak jauh berlatensi tinggi sukses mencapai angka konstan **11.89 MB/s (~95 Mbps)** tanpa indikasi *throttling*.
- **Window Scaling & BBR State:** Pemantauan soket membuktikan algoritma `bbr` mengambil alih *congestion control* secara absolut. Contoh *dump* metrik aktual saat koneksi mencapai beban puncak (*peak load*):
  ```text
  bbr:(bw:39497560bps,mrtt:30.193,pacing_gain:1.25,cwnd_gain:2) send 97322018bps ... rcv_ssthresh:209606 minrtt:30.171 ... snd_wnd:1140992 rcv_wnd:210944
  ```
  **Analisis Metrik:**
  - **`bw:39497560bps`**: BBR mengukur estimasi *bandwidth* asli secara akurat hingga mendekati 40 Mbps pada *stream* tersebut, memungkinkannya mengabaikan *packet loss* biasa.
  - **`snd_wnd:1140992` & `rcv_wnd:210944`**: Efek langsung dari konfigurasi `tcp_rmem` dan `tcp_wmem` raksasa (32 MB). Kernel mengizinkan *Send Window* merenggang lebar hingga melebihi **1.1 MB** per soket tanpa hambatan.
  - **`minrtt:30.171`**: Meskipun batas *window* sedang terbuka penuh dan kecepatan dimaksimalkan, nilai *Round Trip Time* minimum tetap stabil di kisaran 30 ms tanpa menyebabkan efek *bufferbloat* (antrean panjang yang memicu *lag*).

**Kesimpulan Fase 3:**
Penerapan algoritma TCP BBR dan pelebaran batas *buffer* raksasa (`tcp_rmem` dan `tcp_wmem` pada skala 32 MB) berdampak krusial secara langsung. Kombinasi ini sukses mengatasi limitasi *Bandwidth-Delay Product* (BDP), mencegah laju data anjlok (*TCP stall*) akibat fluktuasi ping atau kehilangan paket minor (*packet drop*), dan mengoptimalkan transfer jaringan secara konsisten.

---

## 🏆 Konklusi Akhir
Berdasarkan metrik pengujian di atas, instalasi **CachyOS** pada AMD Ryzen 8845HS ini telah memastikan tingkat sinergi *Low-Latency* dan efisiensi yang nyaris sempurna. Modifikasi mendalam pada tingkat Kernel, Cgroups, **MuQSS Scheduler**, hingga parameter sistem jaringan (Networking/TCP) terbukti bukan sekadar konfigurasi kosmetik, melainkan dapat divalidasi dan diukur efektivitasnya secara nyata dalam mempertahankan keandalan operasional, baik di bawah tekanan memori, I/O disk, maupun utilisasi pita lebar maksimal.
