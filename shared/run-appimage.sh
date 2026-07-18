#!/bin/bash
set -u

if [ "$#" -lt 2 ]; then
    echo "usage: vibe-run-appimage APPDIR APPIMAGE [ARG...]" >&2
    exit 2
fi

app_dir=$1
appimage=$2
app_run="$app_dir/AppRun"
shift 2
error_log=$(mktemp)

cleanup() {
    rm -f "$error_log"
}
trap cleanup EXIT INT TERM

run_appimage() {
    APPDIR="$app_dir" APPIMAGE="$appimage" OWD="$PWD" "$app_run" "$@"
}

set +e
run_appimage "$@" 2>"$error_log"
status=$?
set -e
cat "$error_log" >&2

if [ "$status" -ne 0 ] &&
    grep -Eqi 'running as root without --no-sandbox|no usable sandbox|SUID sandbox helper|failed to move to new namespace|zygote_host_impl_linux' "$error_log"; then
    echo "[w] AppImage sandbox is unavailable; retrying inside the Vibespace isolation boundary." >&2
    set +e
    run_appimage --no-sandbox "$@"
    status=$?
    set -e
fi

exit "$status"
