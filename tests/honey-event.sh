#!/bin/bash
# Prove the event source: an access_log inside a named location records only
# requests that reach the trap, with fields the central server validates.
# Needs nginx (stock is fine) and curl. Usage: bash tests/honey-event.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'nginx -p "$work" -c nginx.conf -s stop 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/logs"
cp -r "$root/honeypot" "$work/honeypot"
# Module-free stand-in for server-ban-nftset-network.conf: same log directive
# and format, with the nftset_autoadd line swapped for its status response.
grep -q 'access_log /var/log/nginx/honeypot-events.log honeypot_event;' \
    "$work/honeypot/server-ban-nftset-network.conf"
sed -e "s#/var/log/nginx/honeypot-events.log#$work/logs/events.log#" \
    -e 's#nftset_autoadd .*#return 410;#' \
    -i "$work/honeypot/server-ban-nftset-network.conf"
cat > "$work/nginx.conf" <<CONF
pid $work/nginx.pid;
error_log $work/logs/error.log;
events {}
http {
    access_log $work/logs/all.log;
    include honeypot/honey.conf;
    include honeypot/log-format-network.conf;
    set_real_ip_from 127.0.0.1;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
    server {
        listen 127.0.0.1:8099;
        include honeypot/server-ban-nftset-network.conf;
        location / { return 200; }
    }
}
CONF
nginx -p "$work" -c nginx.conf -t
nginx -p "$work" -c nginx.conf

fail=0
want() {
    local what=$1
    shift
    if "$@"; then
        echo "ok   $what"
    else
        echo "FAIL $what"
        fail=1
    fi
}

code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'X-Forwarded-For: 203.0.113.9, 198.51.100.7' \
    -H 'Sec-Fetch-Site: cross-site' \
    -H 'User-Agent: probe"quote' \
    'http://127.0.0.1:8099/.env?x=1')
curl -s -o /dev/null http://127.0.0.1:8099/normal
nginx -p "$work" -c nginx.conf -s stop
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$work/nginx.pid" ] || break; sleep 0.2; done

want 'trap answers 410' test "$code" = 410
want 'exactly one event, the trap hit' test "$(wc -l < "$work/logs/events.log")" = 1
python3 - "$work/logs/events.log" <<'PY' || fail=1
import json, sys
e = json.loads(open(sys.argv[1]).readline())
assert e["client"] == "198.51.100.7", e   # rightmost untrusted XFF hop
assert e["peer"] == "127.0.0.1", e        # the real TCP peer
assert e["uri"] == "/.env?x=1", e
assert e["sec_fetch_site"] == "cross-site", e
assert e["ua"] == 'probe"quote', e        # escape=json keeps it parseable
print("ok   event fields")
PY
exit $fail
