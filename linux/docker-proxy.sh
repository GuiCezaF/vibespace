#!/bin/bash
set -eu

VIBE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$VIBE_DIR/lib.sh"

parse_vibe_args "$@"
docker_proxy_main "$@"
print_docker_security_notices
