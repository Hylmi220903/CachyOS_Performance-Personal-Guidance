#!/usr/bin/env fish
# ==============================================================================
# BBRv3 TCP Throughput & Kernel Socket Telemetry Benchmark (Fish Shell)
# ==============================================================================

set -l target_url "https://fsn1-speed.hetzner.com/1GB.bin"
set -l duration 20

if test (count $argv) -ge 1
    set target_url $argv[1]
end

echo "===================================================================="
echo "          BBRv3 TCP Throughput & Socket Telemetry Benchmark        "
echo "===================================================================="
echo "[*] Target Server : $target_url"
echo "[*] Durasi Sampel : $duration detik"
echo "[*] Menginisialisasi single-stream download..."

# Jalankan curl di background
curl -4 -s -o /dev/null $target_url &
set -l curl_pid $last_pid

echo "[*] Curl berjalan (PID: $curl_pid). Menunggu handshake TCP (1.5 detik)..."
sleep 1.5

echo "[*] Memantau metrik kernel TCP BBR (ss)... (Tekan Ctrl+C untuk berhenti)"
echo ""

for i in (seq 1 $duration)
    # Hentikan loop jika proses download selesai lebih awal
    if not kill -0 $curl_pid 2>/dev/null
        echo "[*] Transfer data selesai."
        break
    end

    echo "------------------------ [ Sampel #$i ] ------------------------"
    ss -tin '( dport = :https or dport = :http )' | string match -r '.*(bbr|snd_wnd|minrtt|bytes_acked|send ).*' | while read -l line
        echo " > $line"
    end

    sleep 1
end

# Bersihkan proses curl jika masih aktif
if kill -0 $curl_pid 2>/dev/null
    kill $curl_pid 2>/dev/null
end

echo ""
echo "[*] Pengujian selesai."
