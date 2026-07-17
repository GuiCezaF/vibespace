host_docker_installed() {
    command -v docker >/dev/null 2>&1
}

docker_cli() {
    env -u DOCKER_HOST "$@"
}

docker_socket_responds() {
    local sock=$1

    [ -n "$sock" ] && [ -S "$sock" ] || return 1
    curl --unix-socket "$sock" -sf http://localhost/_ping >/dev/null 2>&1
}

normalize_docker_socket_path() {
    local path=$1

    [ -e "$path" ] || [ -L "$path" ] || return 1
    readlink -f "$path"
}

resolve_host_docker_socket() {
    local candidate normalized

    HOST_DOCKER_SOCK=""

    # rootless docker first when both rootless and rootful daemons exist
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        normalized=$(normalize_docker_socket_path "$candidate" || continue)
        if docker_socket_responds "$normalized"; then
            HOST_DOCKER_SOCK=$normalized
            return 0
        fi
    done < <(printf '%s\n' \
        "$HOME/.docker/run/docker.sock" \
        "${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/docker.sock}")

    normalized=$(normalize_docker_socket_path /var/run/docker.sock || true)
    if docker_socket_responds "$normalized"; then
        HOST_DOCKER_SOCK=$normalized
        return 0
    fi

    return 1
}

host_docker_socket_rootless() {
    local sock=$1

    case "$sock" in
        "$HOME/.docker/run/docker.sock") return 0 ;;
        "${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/docker.sock}") return 0 ;;
        /run/user/*/docker.sock) return 0 ;;
    esac
    return 1
}

docker_daemon_ready() {
    [ -n "${HOST_DOCKER_SOCK:-}" ] || return 1
    docker_cli DOCKER_HOST="unix://$HOST_DOCKER_SOCK" docker info 2>/dev/null | grep -q '^Server:'
}

verify_host_docker_socket() {
    curl --unix-socket "$HOST_DOCKER_SOCK" -sf http://localhost/_ping >/dev/null 2>&1
}

ensure_host_docker() {
    resolve_host_docker_socket || true

    if docker_daemon_ready; then
        return 0
    fi

    log_step "starting host docker daemon"
    if [ -S "$HOME/.docker/run/docker.sock" ] \
        || systemctl --user is-active docker >/dev/null 2>&1 \
        || systemctl --user is-enabled docker >/dev/null 2>&1; then
        systemctl --user start docker >/dev/null 2>&1 || true
    fi
    if systemctl start docker >/dev/null 2>&1; then
        :
    elif systemctl --user start docker >/dev/null 2>&1; then
        :
    else
        log_warn "docker installed but daemon could not be started"
        return 1
    fi

    local attempt
    for attempt in $(seq 1 15); do
        resolve_host_docker_socket || true
        if docker_daemon_ready; then
            return 0
        fi
        sleep 1
    done

    log_warn "docker daemon did not become ready"
    return 1
}

host_user_in_docker_group() {
    id -Gn 2>/dev/null | grep -qx docker
}

host_docker_rootless() {
    local sock=${HOST_DOCKER_SOCK:-}

    [ -n "$sock" ] || return 1
    host_docker_socket_rootless "$sock"
}

host_docker_rootful() {
    local sock=${HOST_DOCKER_SOCK:-}

    [ -n "$sock" ] || return 1
    ! host_docker_socket_rootless "$sock"
}
