#!/bin/bash
# Executar dentro do container vibespace apos o primeiro boot.
# Exemplo: podman exec -it vibespace bash /opt/setup.sh

set -eu

FLUTTER_DIR=/opt/flutter
FLUTTER_REPO=https://github.com/flutter/flutter.git

log:i() { local tag=$1; shift; printf '\033[36;1m[i:%s]\033[m %s\n' "$tag" "$*"; }
log:e() { local tag=$1; shift; printf '\033[31;1m[e:%s]\033[m %s\n' "$tag" "$*"; }
log:w() { local tag=$1; shift; printf '\033[33;1m[w:%s]\033[m %s\n' "$tag" "$*"; }
log:s() { local tag=$1; shift; printf '\033[32;1m[s:%s]\033[m %s\n' "$tag" "$*"; }

command:has() { command -v "$1" >/dev/null 2>&1; }

did_apt_update=false
apt:install() {
    if [ "$did_apt_update" = false ]; then
        log:i apt updating cache...
        apt update
        did_apt_update=true
    fi
    log:i apt installing "$*"
    apt install -y --no-install-recommends "$@"
}

apt:is-installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

apt:install-missing() {
    local pkg installed=() missing=()

    for pkg in "$@"; do
        if apt:is-installed "$pkg"; then
            installed+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done

    if [ ${#installed[@]} -gt 0 ]; then
        log:s apt already installed: "${installed[*]}"
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        apt:install "${missing[@]}"
    fi
}

mise_install() {
    if command:has mise; then
        return 0
    fi

    apt:install-missing gpg
    curl https://mise.run | sh
    if ! grep -q 'mise activate bash' ~/.bashrc; then
        echo 'eval "$(mise activate bash)"' >> ~/.bashrc
    fi
    eval "$(mise activate bash)"
    command:has mise || {
        log:e mise "installation failed, unable to proceed"
        exit 1
    }
}

git_config_install() {
    if [ ! -x /opt/git-configure.sh ]; then
        log:w git-config /opt/git-configure.sh not found, skipping
        log:i you can add this script to setup your email/username and other git config --global ...
        return 0
    fi
    /opt/git-configure.sh
}

cursor_install() {
    if command:has cursor; then
        return 0
    fi

    local debs=()
    shopt -s nullglob
    debs=(/opt/cursor*.deb)
    shopt -u nullglob

    if [ ${#debs[@]} -eq 0 ]; then
        log:w cursor no .deb found in /opt/cursor*.deb, skipping
        return 0
    fi

    yes | apt install -y "${debs[@]}"
    apt update
    apt upgrade -y
}

falkon_install() {
    if command:has falkon; then
        return 0
    fi
    mkdir -p /usr/share/qt5/qtwebengine_dictionaries
    apt:install-missing falkon || apt install -y --fix-missing falkon
}

docker_cli_install() {
    if command:has docker; then
        return 0
    fi

    apt:install-missing ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt update
    apt:install-missing docker-ce-cli docker-buildx-plugin docker-compose-plugin
}

flutter:latest_release_tag() {
    git ls-remote --tags "$FLUTTER_REPO" \
        | awk -F/ '{print $3}' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -1
}

flutter_install() {
    apt:install-missing \
        openjdk-17-jdk clang cmake ninja-build pkg-config libgtk-3-dev \
        mesa-utils lld llvm-20 llvm-20-dev lld-20 git

    if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
        log:s flutter already installed at "$FLUTTER_DIR"
        return 0
    fi

    local latest_tag
    latest_tag=$(flutter:latest_release_tag)
    if [ -z "$latest_tag" ]; then
        log:e flutter unable to resolve latest release tag
        exit 1
    fi

    log:i flutter installing tag "$latest_tag" via git...
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$latest_tag" "$FLUTTER_REPO" "$FLUTTER_DIR"

    export PATH="$FLUTTER_DIR/bin:$PATH"
    if ! grep -q 'flutter/bin' ~/.bashrc; then
        echo 'export PATH="/opt/flutter/bin:$PATH"' >> ~/.bashrc
    fi

    flutter precache
    flutter config --android-sdk=/opt/android-sdk
    flutter --disable-analytics
    flutter doctor -vvv
}

apt:install-missing wget curl git ca-certificates vim rsync ripgrep

mise_install

# command:has gemini || mise use -g node@24 npm:@google/gemini-cli
# command:has task || mise use -g aqua:go-task/task@latest

# opencode
# if ! command:has opencode; then
#     apt:install-missing curl
#     curl -fsSL https://opencode.ai/install | bash
# fi

# antigravity
# if ! command:has antigravity; then
#     apt:install-missing curl gpg
#     mkdir -p /etc/apt/keyrings
#     curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
#         gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
#     echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
#         tee /etc/apt/sources.list.d/antigravity.list > /dev/null
#     apt update
#     apt:install-missing antigravity
# fi

# chrome
# if ! command:has google-chrome-stable; then
#     chrome_deb=/tmp/google-chrome-stable_current_amd64.deb
#     wget -O "$chrome_deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#     apt install -y --no-install-recommends "$chrome_deb"
#     rm -f "$chrome_deb"
# fi

falkon_install
cursor_install

apt modernize-sources -y

git_config_install

apt:install-missing \
    btop maven composer \
    php8.4-{pgsql,mysql,cli,mbstring,common,xml,bcmath,zip} \
    python3-urllib3 python3-requests openjdk-8-jdk \
    curl unzip xz-utils zip libglu1-mesa \
    python3-whisper ffmpeg

flutter_install
docker_cli_install

log:s setup vibespace setup finished
