#!/bin/bash
set -eu

workspace=${1:-/w}
port=${T3_PORT:-3774}
url="http://127.0.0.1:${port}"
log_file=/tmp/vibespace-t3-code.log
browser_url="$url"
server_pid=

stop_server() {
    if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        for _ in $(seq 1 20); do
            if ! kill -0 "$server_pid" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "$server_pid" 2>/dev/null; then
            kill -KILL "$server_pid" 2>/dev/null || true
        fi
        wait "$server_pid" 2>/dev/null || true
    fi
}
trap stop_server EXIT INT TERM

: >"$log_file"
t3 start \
    --mode web \
    --host 127.0.0.1 \
    --port "$port" \
    --no-browser \
    --auto-bootstrap-project-from-cwd \
    "$workspace" >"$log_file" 2>&1 &
server_pid=$!

ready=false
for _ in $(seq 1 60); do
    if grep -q 'Listening on ' "$log_file"; then
        ready=true
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        break
    fi
    sleep 0.25
done
if [ "$ready" != true ]; then
    cat "$log_file" >&2
    echo "T3 Code did not become ready at $url" >&2
    exit 1
fi

pairing_url=
for _ in $(seq 1 20); do
    pairing_url=$(sed -n 's/^[[:space:]]*pairingUrl: //p' "$log_file" | tail -n 1)
    if [ -n "$pairing_url" ]; then
        break
    fi
    sleep 0.05
done
if [ -n "$pairing_url" ]; then
    browser_url="$pairing_url"
fi

echo "[ok] T3 Code is running inside Vibespace: $url"
echo "[i] Close the T3 Code window to finish."
falkon "$browser_url"
