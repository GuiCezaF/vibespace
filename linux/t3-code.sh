#!/bin/bash
set -eu

CONTAINER="${VIBE_CONTAINER:-vibespace}"
T3_PORT="${T3_PORT:-3774}"

unset DOCKER_HOST

for oci in podman docker; do
    command -v "$oci" >/dev/null 2>&1 || continue
    "$oci" ps -q --filter "name=^/${CONTAINER}$" --filter status=running | grep -q . || continue

    printf '[i] starting T3 Code at http://localhost:%s via %s\n' "$T3_PORT" "$oci"
    printf '[i] open the pairing URL printed below; press Ctrl+C to stop\n'
    exec "$oci" exec -it -w /w "$CONTAINER" \
        t3 serve --host 127.0.0.1 --port "$T3_PORT" /w
done

echo "container not running: $CONTAINER (start with ./linux/vibe.sh)" >&2
exit 1
