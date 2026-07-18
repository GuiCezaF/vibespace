#!/bin/sh
set -u

layout=${VIBE_XKB_LAYOUT:-}
variant=${VIBE_XKB_VARIANT:-}
model=${VIBE_XKB_MODEL:-pc105}

if [ -z "$layout" ] || [ -z "${DISPLAY:-}" ]; then
    exit 0
fi

if ! command -v setxkbmap >/dev/null 2>&1; then
    echo "[w] setxkbmap is unavailable; keyboard layout was not configured." >&2
    exit 0
fi

set -- -model "$model" -layout "$layout"
if [ -n "$variant" ]; then
    set -- "$@" -variant "$variant"
fi

if ! setxkbmap "$@" >/dev/null 2>&1; then
    echo "[w] Could not configure keyboard layout: $layout${variant:+($variant)}" >&2
    exit 0
fi

echo "[ok] Keyboard layout configured: $layout${variant:+($variant)}"
