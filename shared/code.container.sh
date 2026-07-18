#!/bin/sh

export DONT_PROMPT_WSL_INSTALL=1

if command -v vibe-configure-keyboard >/dev/null 2>&1; then
    vibe-configure-keyboard
fi

if [ -n "${VIBE_XKB_LAYOUT:-}" ]; then
    exec /usr/bin/code --no-sandbox --ozone-platform=x11 "$@"
fi

exec /usr/bin/code --no-sandbox "$@"
