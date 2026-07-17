#!/bin/sh

export DONT_PROMPT_WSL_INSTALL=1
exec /usr/bin/code --no-sandbox "$@"
