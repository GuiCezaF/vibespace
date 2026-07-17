# Fundamentos compartilhados; carrega modulos reutilizaveis de lib.d/
if [ -n "${VIBE_LIB_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
VIBE_LIB_LOADED=1

if [ -z "${VIBE_DIR:-}" ]; then
    VIBE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
VIBE_ROOT=$(cd "$VIBE_DIR/.." && pwd)
VIBE_SHARED_DIR="${VIBE_SHARED_DIR:-$VIBE_ROOT/shared}"

for lib in "$VIBE_DIR"/lib.d/*.sh; do
    # shellcheck source=/dev/null
    source "$lib"
done
