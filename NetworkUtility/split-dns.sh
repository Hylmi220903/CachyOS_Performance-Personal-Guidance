#!/bin/sh
if [ -n "$TUNDEV" ] && [ -x /usr/bin/resolvectl ]; then
    /usr/bin/resolvectl domain "$TUNDEV" "~telkom.co.id" "~telkom.net" "~telkomakses.co.id" "~telkom.center"
    /usr/bin/resolvectl dnssec "$TUNDEV" no
fi
