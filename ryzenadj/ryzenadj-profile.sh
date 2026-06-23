#!/bin/sh
# 8845HS profile. Staged descent: burst(fast) -> plateau(slow) -> sustained(stapm).
# stapm-time AND slow-time set explicitly: this BIOS resets them on boot, and
# PM-table time-const fields read as garbage (only empirically verifiable).
# Limits (stapm/fast/slow/tctl) ARE read/written accurately.
#   AC      -> fast 45W, plateau 36W, sustained 28W, stapm-time 28, slow-time 6
#              measured: burst ~8s @45W -> ~18-20s @36W plateau -> ~28W (~t40)
#   Battery -> fast 28W, plateau 21W, sustained 15W, stapm-time 15, slow-time 3
#              measured: burst ~3-4s @28W -> ~8-10s @21W plateau -> ~15W (~t20)
#              (also the safe default branch if AC state unreadable)
# Plateau duration grows with stapm-time, shrinks with the slow->stapm GAP
# (rough guide plateau ~= stapm-time/gap, but gap effect is gentler than 1/gap;
# trust empirical numbers above). Managed by Claude. Re-applied by: boot service,
# sleep-hook, udev, 30s timer (re-apply does NOT reset STAPM accum).
if [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = "1" ]; then
    FAST=54000; SLOW=43000; STAPM=30000; STAPMT=28; SLOWT=6
else
    FAST=24000; SLOW=20000; STAPM=15000; STAPMT=15; SLOWT=3
fi
exec /usr/bin/ryzenadj --stapm-limit="$STAPM" --fast-limit="$FAST" --slow-limit="$SLOW" \
    --stapm-time="$STAPMT" --slow-time="$SLOWT" --tctl-temp=90
