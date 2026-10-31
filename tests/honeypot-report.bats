#!/usr/bin/env bats
# Reporter behaviour against a stub curl: batching, offsets, rotation, outages.

setup() {
    ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    W=$(mktemp -d)
    mkdir -p "$W/bin" "$W/conf"
    echo 'REPORT_URL=https://central.example/report' > "$W/conf/report.env"
    echo 'header = "Authorization: Bearer secret-token"' > "$W/conf/report.curl"
    cat > "$W/bin/curl" <<STUB
#!/bin/bash
echo "\$*" >> "$W/argv"
[ ! -e "$W/fail" ] || exit 22
for a in "\$@"; do
    case "\$a" in @*) cat "\${a#@}" >> "$W/received";; esac
done
STUB
    chmod +x "$W/bin/curl"
    export PATH="$W/bin:$PATH"
    export HONEYPOT_REPORT_CONF_DIR="$W/conf"
    export HONEYPOT_EVENT_LOG="$W/events.log"
    export HONEYPOT_REPORT_STATE="$W/report.state"
}

teardown() { rm -rf "$W"; }

run_report() { run "$ROOT/sbin/honeypot-report.sh"; }

@test "no log yet is a clean no-op" {
    run_report
    [ "$status" -eq 0 ]
    [ ! -e "$W/argv" ]
}

@test "sends new events and does not resend them" {
    printf '{"a":1}\n{"a":2}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$status" -eq 0 ]
    [ "$(cat "$W/received")" = $'{"a":1}\n{"a":2}' ]
    run_report
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$W/received")" -eq 2 ]
    printf '{"a":3}\n' >> "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$(wc -l < "$W/received")" -eq 3 ]
    [ "$(tail -n 1 "$W/received")" = '{"a":3}' ]
}

@test "a partial trailing line waits for the next run" {
    printf '{"a":1}\n{"a":' > "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$(cat "$W/received")" = '{"a":1}' ]
    printf '2}\n' >> "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$(tail -n 1 "$W/received")" = '{"a":2}' ]
}

@test "large backlogs split into complete-line batches" {
    export HONEYPOT_REPORT_MAX_BYTES=20
    for i in 1 2 3 4 5 6; do printf '{"event":%s}\n' "$i" >> "$HONEYPOT_EVENT_LOG"; done
    run_report
    [ "$status" -eq 0 ]
    [ "$(cat "$HONEYPOT_EVENT_LOG")" = "$(cat "$W/received")" ]
    [ "$(wc -l < "$W/argv")" -gt 1 ]
}

@test "an outage fails the run and keeps the offset" {
    printf '{"a":1}\n' > "$HONEYPOT_EVENT_LOG"
    touch "$W/fail"
    run_report
    [ "$status" -ne 0 ]
    [ ! -e "$W/received" ]
    rm "$W/fail"
    run_report
    [ "$status" -eq 0 ]
    [ "$(cat "$W/received")" = '{"a":1}' ]
}

@test "rotation drains the old file, then starts the new one at zero" {
    printf '{"a":1}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    printf '{"a":2}\n' >> "$HONEYPOT_EVENT_LOG"
    mv "$HONEYPOT_EVENT_LOG" "$HONEYPOT_EVENT_LOG.1"
    printf '{"a":3}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$status" -eq 0 ]
    [ "$(cat "$W/received")" = $'{"a":1}\n{"a":2}\n{"a":3}' ]
}

@test "a truncated log restarts from the top" {
    printf '{"a":1}\n{"a":2}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    : > "$W/received"
    printf '{"b":1}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    [ "$(cat "$W/received")" = '{"b":1}' ]
}

@test "the token never appears on the curl command line" {
    printf '{"a":1}\n' > "$HONEYPOT_EVENT_LOG"
    run_report
    run grep -q 'secret-token' "$W/argv"
    [ "$status" -ne 0 ]
    grep -q -- '--config' "$W/argv"
}
