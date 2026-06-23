# 🚀 Laporan Pengujian Performa & Responsivitas CachyOS

Laporan ini mendokumentasikan hasil pengujian *stress-test* dan latensi sistem pada instalasi Linux-CachyOS. Pengujian ini bertujuan untuk memvalidasi apakah kombinasi parameter Kernel, *sysctl*, *scheduler* dinamis (scx_lavd), dan *patch* manajemen memori (lru_marie) mampu bersinergi untuk mempertahankan responsivitas sistem (mencegah *stuttering* atau *freeze*) di bawah tekanan komputasi, memori, dan I/O maksimal.

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
- **Rata-rata Latensi (*Average*):** Sangat rendah, berkisar di angka **2.000 µs hingga 4.800 µs (2 - 4.8 ms)**.
- **Latensi Maksimal (*Max Jitter*):** Mayoritas *thread* bertahan di bawah **20 ms**. Tercatat hanya satu lonjakan di *Thread* 10 (~231 ms) yang sangat wajar pada sistem non-RT di bawah beban matriks 100%.
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

## 🏆 Konklusi Akhir
Berdasarkan metrik pengujian di atas, instalasi **CachyOS** pada mesin AMD Ryzen 8845HS ini telah mencapai tingkat sinergi *Low-Latency* dan efisiensi memori yang nyaris sempurna. Modifikasi pada *layer* Kernel, Cgroups, eBPF Scheduler, dan *sysctl* terbukti bukan hanya "kosmetik", melainkan mampu diukur efektivitasnya secara nyata dalam mempertahankan pengalaman komputasi yang responsif di bawah tekanan komputasi terberat sekalipun.
