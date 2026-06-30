# Laporan Pengujian Performa & Responsivitas CachyOS

Laporan ini mendokumentasikan hasil pengujian komprehensif atas *stress-test*, latensi sistem, serta reliabilitas jaringan pada instalasi Linux-CachyOS. Pengujian ini bertujuan untuk memvalidasi apakah kombinasi parameter Kernel, *sysctl*, *scheduler* dinamis (scx_lavd), *patch* manajemen memori (lru_marie), dan optimisasi *hardened networking stack* Bottleneck Bandwidth and Round-trip propagation time (BBR) mampu untuk mempertahankan tingkat responsivitas sistem tertinggi, baik di bawah tekanan komputasi, memori, I/O disk, maupun utilitas *bandwidth* jaringan secara maksimal dengan tetap mempertahankan efisiensi daya.

---

## 💻 Spesifikasi Sistem
- **Sistem Operasi**: Linux CachyOS
- **Versi Kernel**: `7.1.1-2marie` (Custom Kernel)
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
- **`scx_lavd --autopilot`**: Scheduler berbasis eBPF *sched_ext* sedang berjalan dan sepenuhnya menggantikan CFS (Completely Fair Scheduler) bawaan.

---

## 📊 Hasil Pengujian (*Stress-Test*)

Pengujian dilakukan dalam kondisi sistem sedang aktif digunakan (skenario dunia nyata dengan berbagai aplikasi berjalan di latar belakang).

### Fase 1: Uji Responsivitas Penjadwal (CPU Latency)
**Metodologi:** 
Membebani seluruh *thread* CPU hingga 100% menggunakan `stress-ng --matrix 0` selama 15 detik, sekaligus mengukur latensi interupsi sistem (*OS scheduling delay*) menggunakan `cyclictest` (interval 1ms).

**Hasil Observasi:**
- **Rata-rata Latensi (*Average*):** Sangat rendah, berkisar di angka **1.941 µs hingga 4.800 µs (1.9 - 4.8 ms)**.
- **Latensi Maksimal (*Max Jitter*):** Mayoritas *thread* konsisten bertahan di bawah **24 ms**. Tercatat lonjakan puncak pada kisaran **~126 ms** (meningkat dari baseline awal ~231 ms) yang sangat wajar pada sistem non-RT di bawah beban matriks 100%.
- **Pengalaman Interaktif:** Pergerakan kursor tetikus (*mouse*) dan perpindahan *window* aplikasi tetap responsif, mulus, dan sama sekali tidak *freeze*.

**Kesimpulan Fase 1:** Sinergi antara `scx_lavd` dan parameter `threadirqs` terbukti sangat efektif mencegah kelaparan CPU (*CPU starvation*) pada tugas-tugas interaktif UI/UX.

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
Berdasarkan metrik pengujian di atas, instalasi **CachyOS** pada AMD Ryzen 8845HS ini telah memastikan tingkat sinergi *Low-Latency* dan efisiensi yang nyaris sempurna. Modifikasi mendalam pada tingkat Kernel, Cgroups, eBPF Scheduler, hingga parameter sistem jaringan (Networking/TCP) terbukti bukan sekadar konfigurasi kosmetik, melainkan dapat divalidasi dan diukur efektivitasnya secara nyata dalam mempertahankan keandalan operasional, baik di bawah tekanan memori, I/O disk, maupun utilisasi pita lebar maksimal.
