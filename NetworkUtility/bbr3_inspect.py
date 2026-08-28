#!/usr/bin/env python3
"""
BBRv3 TCP Socket State & Version Inspector
Menggunakan getsockopt TCP_CC_INFO (level 26) untuk membaca state machine internal BBRv3 langsung dari kernel.
"""

import socket
import struct
import time
import sys

TARGET_HOST = "1.1.1.1"
TARGET_PORT = 443

if len(sys.argv) > 1:
    TARGET_HOST = sys.argv[1]
if len(sys.argv) > 2:
    TARGET_PORT = int(sys.argv[2])

print(f"[*] Menghubungkan socket TCP ke {TARGET_HOST}:{TARGET_PORT}...")

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((TARGET_HOST, TARGET_PORT))
    s.sendall(b"HEAD / HTTP/1.1\r\nHost: " + TARGET_HOST.encode() + b"\r\n\r\n")
    time.sleep(0.1)
    s.recv(1024)

    # TCP_CC_INFO = 26 di Linux
    raw_info = s.getsockopt(socket.IPPROTO_TCP, 26, 64)
    fmt = "=IIIIIIIII4BIII"
    fields = struct.unpack(fmt, raw_info[:struct.calcsize(fmt)])
    
    phase_names = {
        1: "STARTUP",
        2: "DRAIN",
        3: "PROBE_RTT",
        4: "PROBE_BW_UP",
        5: "PROBE_BW_DOWN",
        6: "PROBE_BW_CRUISE",
        7: "PROBE_BW_REFILL"
    }

    print("\n" + "="*50)
    print("        BBRv3 Kernel Socket State Telemetry       ")
    print("="*50)
    print(f"Algorithm Version (bbr_version) : {fields[12]}")
    print(f"Current State Phase (bbr_phase) : {fields[10]} ({phase_names.get(fields[10], 'UNKNOWN')})")
    print(f"Pacing Gain                     : {fields[3] / 256.0:.2f}")
    print(f"Cwnd Gain                       : {fields[4] / 256.0:.2f}")
    print("="*50)
    s.close()
except Exception as e:
    print(f"[!] Gagal membaca socket TCP: {e}")
