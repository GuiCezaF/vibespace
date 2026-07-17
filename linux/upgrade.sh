#!/bin/bash
set -eu

CONTAINER="${VIBE_CONTAINER:-vibespace}"

unset DOCKER_HOST

for oci in podman docker; do
    command -v "$oci" >/dev/null 2>&1 || continue
    "$oci" ps -q --filter "name=^/${CONTAINER}$" --filter status=running | grep -q . || continue

    printf '[i] upgrading via %s exec %s\n' "$oci" "$CONTAINER"
    "$oci" exec -itu0 "$CONTAINER" fish -c \
        'apt update && apt full-upgrade -y && apt autoremove -y'
    printf '[ok] upgrade finished\n'
    exit 0
done

echo "container not running: $CONTAINER (start with ./linux/vibe.sh)" >&2
exit 1
