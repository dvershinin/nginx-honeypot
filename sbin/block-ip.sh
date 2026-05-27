#!/bin/bash

if [[ -z ${REMOTE_ADDR} ]]; then
    if [[ -z "$1" ]]; then
        echo "REMOTE_ADDR not set!"
        exit 1
    else
        REMOTE_ADDR=$1
    fi
fi

# Trusted IPs that must never be banned (so you don't lock yourself out while
# testing). Override the defaults by editing /etc/nginx/honeypot/trusted-ips.conf
# which simply redefines the TRUSTED_IPS array, e.g.:
#   TRUSTED_IPS=("127.0.0.1" "::1" "203.0.113.7")
TRUSTED_IPS=("127.0.0.1" "::1")
if [[ -f /etc/nginx/honeypot/trusted-ips.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/nginx/honeypot/trusted-ips.conf
fi

for ip in "${TRUSTED_IPS[@]}"; do
    if [[ "$REMOTE_ADDR" == "$ip" ]]; then
        echo "Trusted IP"
        exit 0
    fi
done

# IPv6 addresses contain a colon; everything else is treated as IPv4.
if [[ "$REMOTE_ADDR" == *:* ]]; then
    /sbin/ipset add honeypot6 "${REMOTE_ADDR}"
    /sbin/conntrack -D -s "${REMOTE_ADDR}"
else
    /sbin/ipset add honeypot4 "${REMOTE_ADDR}"
    /sbin/conntrack -D -s "${REMOTE_ADDR}"
fi
