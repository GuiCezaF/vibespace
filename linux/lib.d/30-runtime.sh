resolve_runtime() {
    if [ -z "${VIBE_RUNTIME:-}" ] && [ "$VIBE_INTERACTIVE" = true ] && [ -t 0 ]; then
        read -rp "OCI runtime [podman/docker]: " VIBE_RUNTIME
    fi
    VIBE_RUNTIME=${VIBE_RUNTIME:-podman}
    if ! command -v "$VIBE_RUNTIME" >/dev/null 2>&1; then
        echo "OCI runtime not found: $VIBE_RUNTIME" >&2
        exit 1
    fi
    RUNTIME=$VIBE_RUNTIME
}

resolve_runtime_run_opts() {
    RUNTIME_RUN_OPTS=()
    VOL_PRIVATE=""

    case "$RUNTIME" in
        podman)
            # rootless: map host uid and chown bind mounts for wayland/workspace access
            RUNTIME_RUN_OPTS=(--userns=keep-id)
            VOL_PRIVATE=":U"
            ;;
        docker)
            ;;
        *)
            echo "unsupported runtime: $RUNTIME" >&2
            exit 1
            ;;
    esac
}

podman_rootless() {
    [ "$RUNTIME" = podman ] || return 1
    "$RUNTIME" info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q true
}
