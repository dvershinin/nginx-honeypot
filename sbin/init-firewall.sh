# Script that starts firewall
# Don't forget to chmod 755 this file.
# Adjust the block time as needed (default 7200 seconds).
#!/bin/bash
/usr/sbin/ipset create honeypot4 hash:ip timeout 7200
/usr/sbin/ipset create honeypot6 hash:ip timeout 7200
/usr/sbin/iptables -I INPUT -m set --match-set honeypop4 src -j DROP
/usr/sbin/iptables -I INPUT -m set --match-set honeypot6 src -j DROP
