# Avisos quando o docker do host e rootful: o proxy nao filtra privileged/caps/etc.

warn_rootful_docker_holes() {
    host_docker_rootful || return 0

    log_warn "rootful host docker: extra API restrictions are NOT applied (use rootless when possible)"
    log_warn "  hole: --privileged  | harm: disables container isolation; escape can mean host root"
    log_warn "  hole: --cap-add / setcap  | harm: grants Linux capabilities (e.g. SYS_ADMIN) on the host"
    log_warn "  hole: --network=host  | harm: container uses the host network stack"
    log_warn "  hole: --pid=host  | harm: container can see and signal host processes"
    log_warn "  hole: seccomp/apparmor unconfined  | harm: syscall and MAC confinement removed"
    log_warn "  hole: docker exec --privileged  | harm: escalates a running container after create"
    log_warn "recommend: switch to rootless docker - https://docs.docker.com/engine/security/rootless/#prerequisites"
}

log_rootless_docker_ok() {
    host_docker_rootless || return 0
    log_ok "host docker is rootless at $HOST_DOCKER_SOCK"
}

# Avisos de seguranca no final do setup para nao se perderem no meio do log.
print_docker_security_notices() {
    host_docker_installed || return 0
    [ -n "${HOST_DOCKER_SOCK:-}" ] || return 0

    echo
    if host_docker_rootless; then
        log_rootless_docker_ok
    elif host_docker_rootful; then
        warn_rootful_docker_holes
    fi
}
