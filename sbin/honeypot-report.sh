#!/bin/bash
# Ship new honeypot trap events to the central server, one batch per run.
# The log offset only advances after the server accepts a batch, so an outage
# delays events without losing them. Run from nginx-honeypot-report.timer.
#
# Config, mode 0600 (holds the collector token; passed to curl by file, never
# on argv, where any local user could read it from the process table):
#   /etc/nginx/honeypot/report.env   REPORT_URL=https://...
#   /etc/nginx/honeypot/report.curl  header = "Authorization: Bearer <token>"
set -euo pipefail

CONF_DIR=${HONEYPOT_REPORT_CONF_DIR:-/etc/nginx/honeypot}
LOG=${HONEYPOT_EVENT_LOG:-/var/log/nginx/honeypot-events.log}
STATE=${HONEYPOT_REPORT_STATE:-/var/lib/nginx-honeypot/report.state}
MAX_BYTES=${HONEYPOT_REPORT_MAX_BYTES:-262144}

# shellcheck source=/dev/null
. "$CONF_DIR/report.env"

state_inode=0
state_offset=0
if [ -s "$STATE" ]; then
    read -r state_inode state_offset < "$STATE"
fi

save_state() {
    printf '%s %s\n' "$1" "$2" > "$STATE.tmp"
    mv -f "$STATE.tmp" "$STATE"
}

# Send up to MAX_BYTES of complete lines of $1 from offset $2. Prints the number
# of bytes the server accepted; a trailing partial line waits for the next run.
# Failures must return explicitly: errexit does not apply inside $(send_batch).
send_batch() {
    local file=$1 offset=$2 batch size
    batch=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$batch'" RETURN
    tail -c "+$((offset + 1))" "$file" | head -c "$MAX_BYTES" > "$batch"
    size=$(wc -c < "$batch")
    if [ "$size" -eq 0 ]; then
        echo 0
        return 0
    fi
    # Cut back to the last newline
    while [ "$size" -gt 0 ] && [ "$(tail -c "+$size" "$batch" | head -c 1 | od -An -c | tr -d ' ')" != '\n' ]; do
        size=$((size - 1))
    done
    if [ "$size" -eq 0 ]; then
        echo 0
        return 0
    fi
    truncate -s "$size" "$batch"
    curl --silent --show-error --fail --max-time 30 \
        --config "$CONF_DIR/report.curl" \
        --header 'Content-Type: application/x-ndjson' \
        --data-binary "@$batch" \
        --output /dev/null \
        "$REPORT_URL" >&2 || return 1
    echo "$size"
}

[ -e "$LOG" ] || exit 0
inode=$(stat -c %i "$LOG")

if [ "$inode" != "$state_inode" ]; then
    # Rotated: drain the rest of the old file (delaycompress keeps it as .1)
    if [ "$state_inode" != 0 ] && [ -e "$LOG.1" ] \
            && [ "$(stat -c %i "$LOG.1")" = "$state_inode" ]; then
        while :; do
            sent=$(send_batch "$LOG.1" "$state_offset")
            [ "$sent" -gt 0 ] || break
            state_offset=$((state_offset + sent))
            save_state "$state_inode" "$state_offset"
        done
    fi
    state_inode=$inode
    state_offset=0
    save_state "$state_inode" "$state_offset"
fi

# A truncated log restarts from the top
if [ "$state_offset" -gt "$(wc -c < "$LOG")" ]; then
    state_offset=0
fi

while :; do
    sent=$(send_batch "$LOG" "$state_offset")
    [ "$sent" -gt 0 ] || break
    state_offset=$((state_offset + sent))
    save_state "$state_inode" "$state_offset"
done
