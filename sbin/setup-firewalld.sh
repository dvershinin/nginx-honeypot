#!/bin/bash
# Create the honeypot4/honeypot6 ipsets and wire them into the firewalld
# "drop" zone. Run once after installing nginx-honeypot. Safe to re-run
# (existing sets are kept).
#
# For raw nftables/iptables setups without firewalld, use init-firewall.sh.
set -e

if ! command -v firewall-cmd >/dev/null 2>&1; then
    echo "firewall-cmd not found. Install/enable firewalld first, or use" >&2
    echo "init-firewall.sh for a raw iptables setup, or create the" >&2
    echo "honeypot4/honeypot6 sets and a DROP rule for them by hand." >&2
    exit 1
fi

# Heads-up on EL10 (firewalld defaults to nftables backend): the sets created
# below are nft sets inside firewalld's own table, NOT kernel ipsets. block-ip.sh
# auto-detects this and routes through firewall-cmd, but the indirection is
# slower (~500 ms per ban) than the legacy ipset path (~2 ms). For high-traffic
# EL10 hosts, the Pro `nginx-module-nftset-access` (server-ban-nftset.conf)
# bypasses fcgiwrap entirely and is the recommended path.
if [[ -f /etc/firewalld/firewalld.conf ]] \
   && grep -qE '^FirewallBackend=nftables' /etc/firewalld/firewalld.conf; then
    echo "Notice: firewalld is on the nftables backend (EL10 default)."
    echo "        block-ip.sh will use the portable firewall-cmd path (~500 ms/ban)."
    echo "        For production EL10 traffic, consider the Pro nginx-module-nftset-access"
    echo "        at https://nginx-extras.getpagespeed.com/modules/nftset-access/."
fi

firewall-cmd --permanent --new-ipset=honeypot4 --type=hash:ip \
    --option=maxelem=1000000 --option=family=inet  --option=hashsize=4096 2>/dev/null || true
firewall-cmd --permanent --new-ipset=honeypot6 --type=hash:ip \
    --option=maxelem=1000000 --option=family=inet6 --option=hashsize=4096 2>/dev/null || true

firewall-cmd --permanent --zone=drop --add-source=ipset:honeypot4
firewall-cmd --permanent --zone=drop --add-source=ipset:honeypot6
firewall-cmd --reload

echo "honeypot4/honeypot6 ipsets created and added to the firewalld drop zone."
