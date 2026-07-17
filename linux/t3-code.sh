#!/bin/bash
set -eu

CONTAINER="${VIBE_CONTAINER:-vibespace}"

unset DOCKER_HOST

for oci in podman docker; do
    command -v "$oci" >/dev/null 2>&1 || continue
    "$oci" ps -q --filter "name=^/${CONTAINER}$" --filter status=running | grep -q . || continue

    printf '[i] opening T3 Code inside the container via %s\n' "$oci"
    exec "$oci" exec -it -w /w "$CONTAINER" \
        t3-code /w
done

echo "container not running: $CONTAINER (start with ./linux/vibe.sh)" >&2
exit 1
