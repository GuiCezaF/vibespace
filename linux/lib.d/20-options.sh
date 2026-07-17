VIBE_INTERACTIVE=false

parse_vibe_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -i | --interactive)
                VIBE_INTERACTIVE=true
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "unknown option: $1" >&2
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
}

require_wayland() {
    if [ -z "$WAYLAND_DISPLAY" ] || [ -z "$XDG_RUNTIME_DIR" ]; then
        echo "Wayland passthrough requires WAYLAND_DISPLAY and XDG_RUNTIME_DIR" >&2
        exit 1
    fi
}

set_option() {
    local name=$1 value=$2
    printf -v "$name" '%s' "$value"
    printf '  %s %s\n' "$cyan$name$reset" "$value"
}
