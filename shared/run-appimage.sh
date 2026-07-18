#!/bin/bash
set -u

supervise_appimage() {
    if [ "$#" -lt 3 ]; then
        echo "usage: vibe-run-appimage --supervise APPDIR APPIMAGE OWD [ARG...]" >&2
        return 2
    fi

    local app_dir=$1
    local appimage=$2
    local original_workdir=$3
    local app_run="$app_dir/AppRun"
    local error_log status
    shift 3
    error_log=$(mktemp)

    export APPDIR="$app_dir"
    export APPIMAGE="$appimage"
    export OWD="$original_workdir"
    if [ -n "${VIBE_XKB_LAYOUT:-}" ]; then
        export ELECTRON_OZONE_PLATFORM_HINT=x11
        export MOZ_ENABLE_WAYLAND=0
        export GDK_BACKEND=x11
        export QT_QPA_PLATFORM=xcb
        export SDL_VIDEODRIVER=x11
    fi

    cleanup() {
        rm -f "$error_log"
    }
    trap cleanup EXIT

    run_appimage() {
        "$app_run" "$@"
    }

    if command -v vibe-configure-keyboard >/dev/null 2>&1; then
        vibe-configure-keyboard
    fi

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

    cleanup
    trap - EXIT
    return "$status"
}

if [ "${1:-}" = "--supervise" ]; then
    shift
    supervise_appimage "$@"
    exit $?
fi

if [ "$#" -lt 2 ]; then
    echo "usage: vibe-run-appimage APPDIR APPIMAGE [ARG...]" >&2
    exit 2
fi

app_dir=$1
appimage=$2
shift 2

runner=$(readlink -f "$0")
app_name=$(basename "$appimage")
app_name=${app_name%.*}
state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
log_dir="$state_home/vibespace/appimages"
log_file="$log_dir/$app_name.log"
mkdir -p "$log_dir"

launch_command=(nohup)
if command -v setsid >/dev/null 2>&1; then
    launch_command+=(setsid)
fi
"${launch_command[@]}" "$runner" --supervise "$app_dir" "$appimage" "$PWD" "$@" \
    >>"$log_file" 2>&1 </dev/null &
app_pid=$!

echo "[ok] AppImage started in the background (PID $app_pid): $app_name"
echo "[i] Logs: $log_file"
