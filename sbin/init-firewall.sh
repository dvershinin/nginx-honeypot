#!/bin/bash
# One-shot setup for the no-firewalld case: a raw iptables host that wants the
# honeypot4/honeypot6 kernel ipsets wired directly into INPUT -j DROP.
# If you have firewalld, use setup-firewalld.sh instead.
# Adjust the block time as needed (default 7200 seconds).
/usr/sbin/ipset create honeypot4 hash:ip timeout 7200
/usr/sbin/ipset create honeypot6 hash:ip timeout 7200
/usr/sbin/iptables -I INPUT -m set --match-set honeypot4 src -j DROP
/usr/sbin/iptables -I INPUT -m set --match-set honeypot6 src -j DROP
