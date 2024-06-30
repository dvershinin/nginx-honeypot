#!/bin/bash

if [[ -z ${REMOTE_ADDR} ]]; then
    if [[ -z "$1" ]]; then
        echo "REMOTE_ADDR not set!"
        exit 1
    else
        REMOTE_ADDR=$1
    fi
fi

# Put space separate list of trusted IP addresses, not to lock yourself out if you like to test the honeypot! : )
TRUSTED_IPS=("1.2.3.4" "2.3.4.5" "127.0.0.1")
for ip in "${TRUSTED_IPS[@]}"; do
    if [[ "$REMOTE_ADDR" == "$ip" ]]; then
        echo "Trusted IP"
        exit 0
    fi
done

if [[ "$REMOTE_ADDR" != "${1#*[0-9].[0-9]}" ]]; then
  /sbin/ipset add honeypot4 "${REMOTE_ADDR}"
  /sbin/conntrack -D -s "${REMOTE_ADDR}"
elif [[ "$REMOTE_ADDR" != "${1#*:[0-9a-fA-F]}" ]]; then
  /sbin/ipset add honeypot6 "${REMOTE_ADDR}"
  /sbin/conntrack -D -s "${REMOTE_ADDR}"
else
  echo "Unrecognized IP format '$1'"
fi
