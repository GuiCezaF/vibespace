# Caminhos e constantes compartilhados por vibe.sh.

resolve_vibe_paths() {
    USERID=$(id -u)
    USERNAME=$(id -un)
    WORKSPACE="${WORKSPACE:-/w}"
    VOL_HOME="${VOL_HOME:-$HOME/.vibespace/home}"
    VOL_OPT="${VOL_OPT:-$HOME/.vibespace/opt}"
    PACKAGES_DIR="${PACKAGES_DIR:-$VIBE_ROOT/opt}"
    CONTAINER_NAME="${CONTAINER_NAME:-vibespace}"
    IMAGE_NAME="${IMAGE_NAME:-vibespace:$USERID}"
    SETUP_SCRIPT="$VOL_OPT/setup.sh"
    CPU_LIMIT="${CPU_LIMIT:-6}"
    MEMORY_RAM="${MEMORY_RAM:-3.5g}"
    MEMORY_SWAP="${MEMORY_SWAP:-8g}"
}

print_vibe_paths() {
    set_option RUNTIME "$RUNTIME"
    set_option USERID "$USERID"
    set_option USERNAME "$USERNAME"
    set_option WORKSPACE "$WORKSPACE"
    set_option VOL_OPT "$VOL_OPT"
    set_option PACKAGES_DIR "$PACKAGES_DIR"
    set_option VOL_HOME "$VOL_HOME"
    set_option CONTAINER_NAME "$CONTAINER_NAME"
    set_option IMAGE_NAME "$IMAGE_NAME"
    set_option CPU_LIMIT "$CPU_LIMIT"
    set_option MEMORY_RAM "$MEMORY_RAM"
    set_option MEMORY_SWAP "$MEMORY_SWAP"
    if [ -n "${DOCKER_PROXY_HOST:-}" ]; then
        set_option DOCKER_HOST "$DOCKER_PROXY_HOST"
    fi
}

prepare_vibe_volumes() {
    log_step "preparing volumes"
    mkdir -p "$VOL_HOME" "$VOL_OPT" "$PACKAGES_DIR"
    ensure_setup_script
    log_ok "volumes ready: $VOL_HOME, $VOL_OPT"
}

# Instala /opt/setup.sh uma unica vez; root:root, 0700, sem sobrescrever customizacoes.
ensure_setup_script() {
    if [ -e "$SETUP_SCRIPT" ]; then
        log_ok "setup script already present: $SETUP_SCRIPT"
        return 0
    fi

    log_step "seeding setup script: $SETUP_SCRIPT"
    sudo install -o root -g root -m 0700 \
        "$VIBE_SHARED_DIR/setup.sh" "$SETUP_SCRIPT"
    log_ok "setup script seeded: $SETUP_SCRIPT (root:root, 0700)"
}
