remove_container_with_cmd() {
    local name=$1 label=$2
    shift 2
    local -a cmd=()
    local id

    [ $# -gt 0 ] || return 0
    cmd=("$@")
    command -v "${cmd[0]}" >/dev/null 2>&1 || return 0

    id=$("${cmd[@]}" ps -a -q -f "name=^/${name}$" 2>/dev/null || true)
    [ -n "$id" ] || return 0

    log_step "removing $label: $name (${cmd[*]})"
    if "${cmd[@]}" rm -f "$name" >/dev/null 2>&1; then
        log_ok "removed $label: $name"
        return 0
    fi

    log_warn "could not remove $label: $name (${cmd[*]})"
    return 1
}

remove_container_everywhere() {
    local name=$1 label=${2:-container}

    remove_container_with_cmd "$name" "$label" podman
    if command -v sudo >/dev/null 2>&1; then
        remove_container_with_cmd "$name" "$label" sudo podman
    fi
    remove_container_with_cmd "$name" "$label" docker
}
