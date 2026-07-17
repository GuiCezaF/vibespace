#!/bin/bash
set -eu

APPLY=false
VOL_HOME="${VOL_HOME:-$HOME/.vibespace/home}"
VOL_OPT="${VOL_OPT:-$HOME/.vibespace/opt}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--apply]

Default is dry-run. Pass --apply to execute removals.
EOF
}

log() {
    printf '[i] %s\n' "$*"
}

warn() {
    printf '[w] %s\n' "$*" >&2
}

run() {
    if [ "$APPLY" = true ]; then
        log "run: $*"
        "$@"
    else
        log "[dry-run] $*"
    fi
}

oci_available() {
    command -v "$1" >/dev/null 2>&1
}

oci_vibespace_container() {
    case "$1" in
        vibespace | vibespace-* ) return 0 ;;
    esac
    return 1
}

oci_cleanup_containers() {
    local oci=$1 ids id name remove=()

    ids=$("$oci" ps -aq 2>/dev/null || true)
    [ -n "$ids" ] || return 0

    for id in $ids; do
        name=$("$oci" inspect -f '{{.Name}}' "$id" 2>/dev/null | sed 's|^/||' || true)
        [ -n "$name" ] || continue
        oci_vibespace_container "$name" && continue
        remove+=("$id")
    done

    [ ${#remove[@]} -gt 0 ] || return 0
    run "$oci" rm -f "${remove[@]}"
}

oci_cleanup_prune() {
    local oci=$1

    run "$oci" image prune -af
    run "$oci" network prune -f
    run "$oci" builder prune -af

    if "$oci" buildx version >/dev/null 2>&1; then
        run "$oci" buildx prune -af
    fi
}

oci_volume_named() {
    local oci=$1 vol=$2
    local project volume

    project=$("$oci" volume inspect -f '{{index .Labels "com.docker.compose.project"}}' "$vol" 2>/dev/null || true)
    volume=$("$oci" volume inspect -f '{{index .Labels "com.docker.compose.volume"}}' "$vol" 2>/dev/null || true)
    [ -n "$project" ] || [ -n "$volume" ]
}

oci_cleanup_volumes() {
    local oci=$1 vol

    while IFS= read -r vol; do
        [ -n "$vol" ] || continue
        if oci_volume_named "$oci" "$vol"; then
            log "skip named volume on $oci: $vol"
            continue
        fi
        run "$oci" volume rm "$vol"
    done < <("$oci" volume ls -q 2>/dev/null || true)
}

oci_cleanup() {
    local oci=$1

    oci_available "$oci" || return 0
    log "oci cleanup: $oci"
    oci_cleanup_containers "$oci"
    oci_cleanup_prune "$oci"
    oci_cleanup_volumes "$oci"
}

remove_path() {
    local path=$1

    [ -e "$path" ] || return 0
    run rm -rf "$path"
}

remove_home() {
    remove_path "$VOL_HOME/$1"
}

remove_opt() {
    remove_path "$VOL_OPT/$1"
}

cleanup_cache_paths() {
    log "cache cleanup: $VOL_HOME $VOL_OPT"

    remove_home .cache
    remove_home .config/Cursor/Cache
    remove_home .config/Cursor/CachedData
    remove_home ".config/Cursor/Code Cache"
    remove_home .config/Cursor/GPUCache
    remove_home .config/Cursor/logs
    remove_home .config/Cursor/Crashpad
    remove_home .config/Antigravity/Cache
    remove_home .config/Antigravity/CachedData
    remove_home ".config/Antigravity/Code Cache"
    remove_home .config/Antigravity/GPUCache
    remove_home .config/Antigravity/logs
    remove_home .bun
    remove_home .npm
    remove_home .local/share/pnpm
    remove_home .yarn
    remove_home .local/share/mise/downloads
    remove_home .gradle
    remove_home .m2
    remove_home .pub-cache
    remove_home .dart-tool

    remove_opt flutter/bin/cache
    remove_opt android-sdk/.temp
    remove_opt android-sdk/build-cache
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)
            APPLY=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

unset DOCKER_HOST

if [ "$APPLY" = true ]; then
    log "mode: apply"
else
    log "mode: dry-run (pass --apply to execute)"
fi

for oci in docker podman; do
    oci_cleanup "$oci"
done

cleanup_cache_paths

if [ "$APPLY" = true ]; then
    log "cleanup finished"
else
    warn "dry-run only; re-run with --apply to execute"
fi
