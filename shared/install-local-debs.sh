#!/bin/bash
set -eu

packages_dir=${1:-/packages}
debs=()

shopt -s nullglob
debs=("$packages_dir"/*.deb)
shopt -u nullglob

if [ ${#debs[@]} -eq 0 ]; then
    echo "[i] No local .deb packages found in $packages_dir; skipping."
    exit 0
fi

echo "[i] Installing local .deb packages from $packages_dir"
apt-get update
apt-get install -y --no-install-recommends "${debs[@]}"
apt-get clean
rm -rf /var/lib/apt/lists/*
echo "[ok] Local .deb packages installed."
