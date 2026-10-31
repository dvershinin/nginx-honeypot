#!/bin/bash
# Load honeypot/honey.conf + honeypot/server.conf into a throwaway nginx and
# assert which request URIs count as honey (410) and which must pass (200).
# Needs nginx and curl. Usage: bash tests/honey-match.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'nginx -p "$work" -c nginx.conf -s stop 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/logs"
cp -r "$root/honeypot" "$work/honeypot"
cat > "$work/nginx.conf" <<CONF
pid $work/nginx.pid;
error_log $work/logs/error.log;
events {}
http {
    access_log off;
    include honeypot/honey.conf;
    server {
        listen 127.0.0.1:8099;
        include honeypot/server.conf;
        location / { return 200; }
    }
}
CONF
nginx -p "$work" -c nginx.conf -t
nginx -p "$work" -c nginx.conf

fail=0
check() {
    local want=$1 uri=$2 got
    got=$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "http://127.0.0.1:8099$uri")
    if [ "$got" = "$want" ]; then
        echo "ok   $got $uri"
    else
        echo "FAIL $got (want $want) $uri"
        fail=1
    fi
}

# Honey: WP template-hierarchy LFI (pagename traversal) and pearcmd probes
check 410 '/?page_id=1&pagename=templates%252f%252e%252e%252fwp-links-opml'
check 410 '/?page_id=1&pagename=templates%252F%252E%252E%252Fwp-links-opml'
check 410 '/?page_id=1&pagename=templates%25252f%25252e%25252e%25252fx'
check 410 '/?page_id=1&pagename=templates%2f%2e%2e%2fx'
check 410 '/?page_id=1&pagename=templates/../x'
check 410 '/?pagename=layouts%252f..%252fusr%252fshare%252fphp%252fx'
check 410 '/index.php?+config-create+/tmp/x.php'
check 410 '/?x=/usr/share/pear/pearcmd'
check 410 '/?lang=../../../usr/local/lib/php/peclcmd'
check 410 '/index.php?-d+allow_url_include%3d1+-d+auto_prepend_file%3dphp://input'
check 410 '/?file=php%3A%2F%2Ffilter/resource=index'
# Not honey: WordPress uses these params legitimately
check 200 '/?pagename=about'
check 200 '/?page_id=1'
check 200 '/?page_id=1&pagename=about-us'
check 200 '/blog/config-create-guide'
check 200 '/?s=php+tutorial'
# Existing path honey still trips
check 410 '/phpmyadmin/'
check 410 '/.env'
check 410 '/.git/config'
check 410 '/app/.env'
check 410 '/.well-known'
check 410 '/.well-known/../.env'
check 410 '/actuator/env'
check 410 '/actuator/heapdump'
# Not honey: RFC 8615 tree, monitor endpoints, dot-paths in the query string
check 200 '/.well-known/acme-challenge/token'
check 200 '/.well-known/security.txt'
check 200 '/actuator/health'
check 200 '/login?next=/.hidden/page'

exit $fail
