DOCKER_PROXY_NAME="${VIBE_DOCKER_PROXY_NAME:-vibespace-docker-proxy}"
DOCKER_PROXY_PORT="${VIBE_DOCKER_PROXY_PORT:-2375}"
DOCKER_PROXY_IMAGE="${VIBE_DOCKER_PROXY_IMAGE:-docker.io/wollomatic/socket-proxy:1.12.2}"
DOCKER_PROXY_HOST="tcp://127.0.0.1:${DOCKER_PROXY_PORT}"
DOCKER_PROXY_CMD=()
DOCKER_PROXY_RUN_OPTS=()

docker_proxy_rootful_enabled() {
    case "${VIBE_DOCKER_PROXY_ROOTFUL:-}" in
        1 | true | yes) return 0 ;;
        0 | false | no) return 1 ;;
    esac
    # rootful proxy only when the selected socket is rootful (/var/run/docker.sock)
    host_docker_rootful
}

resolve_docker_proxy_cmd() {
    # proxy container always uses RUNTIME (default podman)
    DOCKER_PROXY_CMD=("$RUNTIME")

    if docker_proxy_rootful_enabled && [ "$RUNTIME" = podman ]; then
        if command -v sudo >/dev/null 2>&1; then
            DOCKER_PROXY_CMD=(sudo "$RUNTIME")
        else
            log_warn "VIBE_DOCKER_PROXY_ROOTFUL=1 but sudo not found"
        fi
    fi
}

resolve_docker_proxy_run_opts() {
    DOCKER_PROXY_RUN_OPTS=()

    if docker_proxy_rootful_enabled; then
        if [ "$RUNTIME" = podman ]; then
            DOCKER_PROXY_RUN_OPTS=(--userns=host)
        fi
        if getent group docker >/dev/null 2>&1; then
            DOCKER_PROXY_RUN_OPTS+=(--group-add "$(getent group docker | cut -d: -f3)")
        fi
        return
    fi

    if podman_rootless || host_docker_rootless; then
        # rootless docker.sock or rootless podman: keep host supplementary groups for socket access
        DOCKER_PROXY_RUN_OPTS=(
            --group-add keep-groups
            --annotation run.oci.keep_original_groups=1
        )
        if ! host_user_in_docker_group && ! host_docker_rootless; then
            log_warn "user not in docker group; add yourself or use rootful host docker"
        fi
        return
    fi

    if getent group docker >/dev/null 2>&1; then
        DOCKER_PROXY_RUN_OPTS=(--group-add "$(getent group docker | cut -d: -f3)")
    else
        log_warn "docker group not found on host; proxy may not reach docker.sock"
    fi
}

docker_proxy_socket_ownership() {
    "${DOCKER_PROXY_CMD[@]}" exec "$DOCKER_PROXY_NAME" ls -la /var/run/docker.sock 2>&1 || true
}

remove_docker_proxy() {
    remove_container_everywhere "$DOCKER_PROXY_NAME" "docker proxy"
}

start_docker_proxy() {
    local -a proxy_env=(
        -e SP_LISTENIP=127.0.0.1
        -e SP_PROXYPORT=2375
        -e SP_ALLOWFROM=127.0.0.1/32
        -e SP_SOCKETPATH=/var/run/docker.sock
        -e SP_ALLOWBINDMOUNTFROM=/w
        -e SP_LOGLEVEL=INFO
    )

    docker_proxy_append_allowlist_env proxy_env GET DOCKER_PROXY_ALLOW_GET
    docker_proxy_append_allowlist_env proxy_env HEAD DOCKER_PROXY_ALLOW_HEAD
    docker_proxy_append_allowlist_env proxy_env POST DOCKER_PROXY_ALLOW_POST
    docker_proxy_append_allowlist_env proxy_env PUT DOCKER_PROXY_ALLOW_PUT
    docker_proxy_append_allowlist_env proxy_env DELETE DOCKER_PROXY_ALLOW_DELETE

    resolve_docker_proxy_cmd
    resolve_docker_proxy_run_opts

    log_step "creating docker proxy: $DOCKER_PROXY_NAME (socket: $HOST_DOCKER_SOCK)"
    # --net host: client IP stays 127.0.0.1; -p publish would show the bridge IP and fail SP_ALLOWFROM
    "${DOCKER_PROXY_CMD[@]}" run -d \
        --net host \
        "${DOCKER_PROXY_RUN_OPTS[@]}" \
        --name "$DOCKER_PROXY_NAME" \
        -v "${HOST_DOCKER_SOCK}:/var/run/docker.sock:ro" \
        "${proxy_env[@]}" \
        "$DOCKER_PROXY_IMAGE" >/dev/null
    log_ok "docker proxy running on $DOCKER_PROXY_HOST"
}

verify_docker_proxy() {
    local attempt

    if ! verify_host_docker_socket; then
        log_warn "host docker socket is not responding: $HOST_DOCKER_SOCK"
        return 1
    fi

    if ! "${DOCKER_PROXY_CMD[@]}" exec "$DOCKER_PROXY_NAME" test -S /var/run/docker.sock 2>/dev/null; then
        log_warn "docker proxy cannot see mounted socket"
        log_warn "check: ${DOCKER_PROXY_CMD[*]} exec $DOCKER_PROXY_NAME ls -la /var/run/docker.sock"
        return 1
    fi

    for attempt in $(seq 1 15); do
        if curl -sf "http://127.0.0.1:${DOCKER_PROXY_PORT}/_ping" >/dev/null 2>&1; then
            log_ok "docker proxy verified on $DOCKER_PROXY_HOST"
            return 0
        fi
        sleep 1
    done

    log_warn "docker proxy not responding on $DOCKER_PROXY_HOST"
    if curl -s "http://127.0.0.1:${DOCKER_PROXY_PORT}/_ping" 2>/dev/null | grep -qi forbidden; then
        log_warn "proxy returned Forbidden; check SP_ALLOWFROM matches client IP (proxy uses --net host for localhost)"
    fi
    log_warn "socket inside proxy: $(docker_proxy_socket_ownership)"
    log_warn "proxy cannot reach docker.sock backend; rootless setups need keep-groups or rootful host docker"
    log_warn "check: ${DOCKER_PROXY_CMD[*]} logs $DOCKER_PROXY_NAME"
    return 1
}

ensure_docker_proxy() {
    if ! host_docker_installed; then
        log_step "docker not installed on host, skipping proxy"
        return 0
    fi

    log_step "ensuring host docker daemon is running"
    if ! ensure_host_docker; then
        log_warn "skipping docker proxy setup"
        return 0
    fi
    log_ok "host docker daemon is ready at $HOST_DOCKER_SOCK"

    if host_docker_rootless; then
        log_step "proxying rootless host docker via $RUNTIME (keep-groups)"
    elif docker_proxy_rootful_enabled; then
        log_step "proxying rootful host docker via sudo $RUNTIME (--userns=host)"
    fi

    remove_docker_proxy
    start_docker_proxy
    verify_docker_proxy || log_warn "docker proxy verification failed; docker CLI may not work until ./linux/docker-proxy.sh succeeds"
}

docker_proxy_main() {
    if [ -z "${RUNTIME:-}" ]; then
        resolve_runtime
    fi
    ensure_docker_proxy
}
