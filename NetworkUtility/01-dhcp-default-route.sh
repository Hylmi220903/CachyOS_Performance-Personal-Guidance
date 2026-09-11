#!/bin/bash
# ==============================================================================
# Auto-restore default route (RFC 3442 fix) & Clean DNS for 10.x.x.x networks
# ==============================================================================

IFACE="$1"
ACTION="$2"

# Filter out virtual / tunnel interfaces
case "$IFACE" in
    lo|tun*|tap*|wg*|docker*|br*|veth*|virbr*|"")
        exit 0
        ;;
esac

case "$ACTION" in
    up|dhcp4-change|reapply)
        # 1. Default Route Restoration (RFC 3442 fix)
        if ! ip -4 route show default dev "$IFACE" | grep -q default; then
            ROUTER="${DHCP4_ROUTERS%% *}"
            if [ -z "$ROUTER" ]; then
                ROUTER=$(nmcli -f DHCP4 device show "$IFACE" 2>/dev/null | grep -E '\brouters\s*=' | grep -v 'requested' | awk -F'= ' '{print $2}' | awk '{print $1}')
            fi

            if [ -n "$ROUTER" ] && [[ "$ROUTER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                METRIC=$(ip -4 route show dev "$IFACE" proto kernel scope link 2>/dev/null | grep -oP 'metric \K[0-9]+' | head -n1)
                if [ -z "$METRIC" ]; then
                    if [[ "$IFACE" =~ ^wl ]]; then
                        METRIC=600
                    else
                        METRIC=100
                    fi
                fi

                ip route replace default via "$ROUTER" dev "$IFACE" metric "$METRIC"
                logger -t "nm-dispatcher-dhcp" "Auto-restored default route via $ROUTER on $IFACE (metric $METRIC)"
            fi
        fi

        # 2. DNS Sanitization for 10.x.x.x networks:
        # If the interface has a 10.x.x.x IP or receives Telkom internal DNS (10.x.x.x),
        # point this interface to Quad9/Cloudflare (9.9.9.9/1.1.1.1) so general internet
        # (browsing, Antigravity, OneDrive, downloads) has full uninhibited speed with zero 12s freezes.
        # Office domains (~telkom.co.id, etc.) remain handled by OpenConnect (tun0).
        IFACE_IP=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
        if [[ "$IFACE_IP" =~ ^10\. ]] || [[ "$DHCP4_DOMAIN_NAME_SERVERS" =~ 10\. ]]; then
            if command -v resolvectl >/dev/null 2>&1; then
                resolvectl dns "$IFACE" 9.9.9.9 1.1.1.1 2620:fe::fe 2606:4700:4700::1111 2>/dev/null || true
                resolvectl default-route "$IFACE" true 2>/dev/null || true
                resolvectl dnsovertls "$IFACE" no 2>/dev/null || true
                logger -t "nm-dispatcher-dhcp" "Sanitized DNS for 10.x.x.x interface $IFACE (assigned 9.9.9.9/1.1.1.1)"
            fi
        fi
        ;;
esac

exit 0
