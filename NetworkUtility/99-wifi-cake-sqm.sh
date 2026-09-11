#!/bin/bash
# ==============================================================================
# Dynamic CAKE SQM per SSID for NetworkManager
# ==============================================================================

IFACE="$1"
ACTION="$2"

if [[ "$IFACE" != wlan* ]]; then
    exit 0
fi

case "$ACTION" in
    up|dhcp4-change|dhcp6-change|reapply)
        SSID=$(iw dev "$IFACE" link 2>/dev/null | grep -oP "SSID: \\K.*")
        if [ -z "$SSID" ]; then
            SSID="$CONNECTION_ID"
        fi

        case "$SSID" in
            *"SemangatPagi!-Game"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 40mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 41Mbit (Down target 143Mbit)"
                ;;
            *"POCO-F6"*|*"POCO F6"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 30mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 30Mbit (Down target 50Mbit)"
                ;;
            *"Lokale Select MT Haryono"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 8mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 8Mbit (Down target 8Mbit)"
                ;;
            *"Lokale Select Sudirman"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 40mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 40Mbit (Down target 70Mbit)"
                ;;
            *"ROCVI"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 25mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 25Mbit (Down target 95Mbit)"
                ;;
            *"@28FINEST"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 6mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 6Mbit (Down target 10Mbit)"
                ;;
            *"Team SO-FF PAMASUKA"*)
                tc qdisc replace dev "$IFACE" root cake bandwidth 450mbit diffserv3 ack-filter overhead 44 mpu 64
                logger -t "cake-sqm" "Applied CAKE profile for SSID '$SSID': Up 450Mbit (Down target 300Mbit)"
                ;;
            *)
                tc qdisc del dev "$IFACE" root 2>/dev/null; tc qdisc add dev "$IFACE" root cake diffserv3 ack-filter
                logger -t "cake-sqm" "Applied CAKE unlimited profile for SSID '$SSID'"
                ;;
        esac
        ;;
    down)
        tc qdisc del dev "$IFACE" root 2>/dev/null
        ;;
esac
