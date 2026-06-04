#!/bin/bash
# block-ip.sh — append an offending IP to whichever firewall backend is active.
#
# Usage:
#   REMOTE_ADDR=1.2.3.4 block-ip.sh        (CGI path via block-ip.cgi)
#   block-ip.sh 1.2.3.4                    (manual / debug path)
#
# Backends supported (auto-detected, cached in /run/nginx-honeypot.backend):
#   1. ipset     - legacy kernel ipset (EL7/8/9 firewalld+iptables, raw iptables).
#                  Fast path (~2 ms).
#   2. firewalld - firewall-cmd --ipset=...  (works on either FirewallBackend;
#                  required for EL10 where firewalld defaults to nftables and
#                  legacy /sbin/ipset no longer sees the set). ~500 ms.
#   3. nft       - raw nftables, no firewalld. nft add element ip[6] filter ...

set -u

if [[ -z "${REMOTE_ADDR:-}" ]]; then
    if [[ -z "${1:-}" ]]; then
        echo "REMOTE_ADDR not set!" >&2
        exit 1
    fi
    REMOTE_ADDR=$1
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
    family=6
    nft_family=ip6
else
    family=4
    nft_family=ip
fi
set_name="honeypot${family}"

CACHE=/run/nginx-honeypot.backend

detect_backend() {
    # 1) Legacy kernel ipset — fast path. Hits on EL7/8/9 firewalld+iptables
    #    (firewall-cmd --new-ipset created a real kernel ipset on those) and on
    #    raw-iptables hosts set up via init-firewall.sh.
    if command -v ipset >/dev/null 2>&1 \
       && ipset list -n 2>/dev/null | grep -qx "$set_name"; then
        echo "ipset"
        return
    fi
    # 2) firewalld with EITHER backend has the set registered. The only
    #    portable add path on EL10 (firewalld+nftables default) — firewalld
    #    stores its sets inside its own nft table, invisible to /sbin/ipset.
    if command -v firewall-cmd >/dev/null 2>&1 \
       && firewall-cmd --get-ipsets 2>/dev/null | tr ' ' '\n' | grep -qx "$set_name"; then
        echo "firewalld"
        return
    fi
    # 3) Raw nftables (no firewalld). User created `ip filter` table +
    #    honeypot4/honeypot6 set by hand or via a Pro module setup script.
    if command -v nft >/dev/null 2>&1 \
       && nft list set "$nft_family" filter "$set_name" >/dev/null 2>&1; then
        echo "nft"
        return
    fi
    echo "none"
}

# Cache backend across requests. /run is tmpfs — cleared on reboot, so any
# backend swap during host reconfig auto-redetects after the next reboot
# without further plumbing. Best-effort write (read-only /run stays harmless).
if [[ -r "$CACHE" ]]; then
    backend=$(cat "$CACHE")
else
    backend=$(detect_backend)
    # Subshell so bash's "cannot open" error (if /run is read-only or missing)
    # is captured by 2>/dev/null - a bare `> "$CACHE" 2>/dev/null` doesn't, since
    # the redirection is opened BEFORE stderr is redirected.
    ( echo "$backend" > "$CACHE" ) 2>/dev/null || true
fi

case "$backend" in
    ipset)
        /sbin/ipset add "$set_name" "$REMOTE_ADDR" 2>/dev/null || true
        ;;
    firewalld)
        firewall-cmd --ipset="$set_name" --add-entry="$REMOTE_ADDR" >/dev/null 2>&1 || true
        ;;
    nft)
        nft add element "$nft_family" filter "$set_name" "{ $REMOTE_ADDR }" 2>/dev/null || true
        ;;
    *)
        echo "block-ip.sh: no firewall backend with $set_name found; $REMOTE_ADDR not banned." >&2
        echo "  Run /usr/libexec/nginx-honeypot/setup-firewalld.sh (firewalld hosts) or" >&2
        echo "  /usr/libexec/nginx-honeypot/init-firewall.sh (raw iptables) first." >&2
        exit 1
        ;;
esac

# Drop existing TCP state from this source regardless of how the future-drop
# is implemented. Silently skip if conntrack-tools isn't installed.
if command -v conntrack >/dev/null 2>&1; then
    /sbin/conntrack -D -s "$REMOTE_ADDR" >/dev/null 2>&1 || true
fi
