# Vibespace

Isolated development environment on Ubuntu 24.04 LTS. Linux hosts get Wayland GUI passthrough; Windows 11 hosts get a native PowerShell lifecycle and Docker Desktop integration. A filtered Docker API proxy lets the environment create project containers without receiving the raw Docker socket.

The image includes Visual Studio Code, Codex CLI, T3 Code, mise, the latest
Node.js LTS, and the latest stable Go toolchain out of the box.

## Project structure

```text
linux/    Linux lifecycle, proxy, cleanup, and Fish integration
windows/  Windows 11 PowerShell and CMD entrypoints
shared/   Container image, mise config, app wrappers, and bootstrap script
opt/      Drop-in folder for local .deb installers (not committed)
```

## Linux prerequisites

- Linux with Wayland (`WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` set on the host)
- [Podman](https://podman.io/) or [Docker](https://docs.docker.com/engine/install/) on the host
- Host Docker daemon when you want docker CLI inside vibespace to manage project containers (rootless preferred when available)
- Fish shell on the host (optional, for `vibe` / `viberoot` helpers)

## Quick start

```bash
chmod +x linux/*.sh
./linux/vibe.sh
```

This builds the image, recreates the docker socket proxy, starts the `vibespace` container, and installs host fish config to `~/.config/fish/conf.d/vibespace.fish`.

Enter the environment:

```bash
vibe
# or
podman exec -it vibespace fish
```

## Scripts

| Script | Purpose |
|--------|---------|
| `linux/vibe.sh` | Full setup: proxy + image + container + host fish config |
| `linux/t3-code.sh` | Open the containerized T3 Code interface through Wayland |
| `linux/cleanup.sh` | Dry-run by default; `--apply` prunes docker/podman and cache paths |
| `linux/upgrade.sh` | `apt full-upgrade` inside running vibespace container |
| `linux/docker-proxy.sh` | Recreate only the wollomatic docker socket proxy |
| `windows/vibe.cmd` | Windows 11 entrypoint for all lifecycle commands |
| `windows/vibe.windows.ps1` | Complete Windows 11 lifecycle through Docker Desktop |
| `shared/Containerfile` | Shared Ubuntu development image |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VIBE_RUNTIME` | `podman` | OCI runtime for vibespace (`podman` or `docker`). Use `-i` to pick interactively |
| `VIBE_DOCKER_PROXY_ROOTFUL` | auto | Force rootful proxy (`1`) or disable (`0`). Auto only when proxying `/var/run/docker.sock` |
| `CPU_LIMIT` | `6` | CPU limit for vibespace container |
| `MEMORY_RAM` | `3.5g` | Memory limit |
| `MEMORY_SWAP` | `8g` | Memory + swap limit |
| `VIBE_DOCKER_PROXY_IMAGE` | `docker.io/wollomatic/socket-proxy:1.12.2` | Socket proxy image |

Pass `-i` or `--interactive` to `linux/vibe.sh` / `linux/docker-proxy.sh` when you want prompts (for example OCI runtime selection). Scripts are non-interactive by default.

### cleanup.sh

Self-contained script. Loops **docker** then **podman**:

- Removes all containers except names starting with `vibespace`
- Prunes images, networks, builder, and buildx
- Removes volumes without compose labels (named compose volumes are kept)
- Deletes rebuildable caches under `~/.vibespace/home` and `~/.vibespace/opt`

Default is **dry-run**. Pass `--apply` to execute.

```bash
./linux/cleanup.sh           # dry-run
./linux/cleanup.sh --apply   # execute
```

### upgrade.sh

Runs apt upgrade inside the running vibespace container (podman or docker, whichever has it running):

```bash
./linux/upgrade.sh
```

## Layout

Host paths:

- `/w` - workspace (bind-mounted into the container)
- `~/.vibespace/home` - persistent home inside vibespace
- `~/.vibespace/opt` - persistent extra tools and SDKs (mounted at `/opt`)
- `./opt` - local `.deb` input folder (mounted read-only at `/packages`)

Inside the container:

- User matches host UID; shell is fish
- `DOCKER_HOST=tcp://127.0.0.1:2375` (filtered host docker API via proxy)

## Docker proxy

Project containers run on the **host** docker daemon. Vibespace uses Podman for its own container and proxy; the proxy exposes host docker over TCP instead of mounting `docker.sock` into vibespace.

The proxy is [wollomatic/socket-proxy](https://github.com/wollomatic/socket-proxy) with a **deny-by-default** API allowlist ([linux/lib.d/50-docker-proxy-allowlist.sh](linux/lib.d/50-docker-proxy-allowlist.sh)) and bind mounts restricted to `/w` (`SP_ALLOWBINDMOUNTFROM=/w`). Named volumes stay allowed so compose stacks can persist database data.

The proxy container uses **`--net host`** and listens on `127.0.0.1:2375` so `SP_ALLOWFROM=127.0.0.1/32` matches clients (vibespace also uses host networking). Port publish would make wollomatic see the bridge IP and return Forbidden.

Socket selection prefers rootless docker (`~/.docker/run/docker.sock`, then `$XDG_RUNTIME_DIR/docker.sock`). Rootful `/var/run/docker.sock` is used only when rootless is not available. Rootful sockets need `sudo podman --userns=host` on the proxy; rootless sockets use `keep-groups`.

### Already blocked

| Control | How |
|---------|-----|
| Vibespace direct socket | `vibe.sh` does not mount `docker.sock`; only sets `DOCKER_HOST=tcp://127.0.0.1:2375` |
| Project bind to host paths outside `/w` | Proxy bind filter (including `/var/run/docker.sock`) |
| Mass / daemon APIs | Not in allowlist (`prune`, `system`, `swarm`, `docker cp`, etc.) |

### Rootful docker warnings

When the host uses a **rootful** socket, `vibe.sh` / `docker-proxy.sh` print one `[w]` per hole the proxy does **not** filter, plus a recommendation to use [rootless Docker](https://docs.docker.com/engine/security/rootless/#prerequisites):

| Hole | Harm |
|------|------|
| `--privileged` | Disables container isolation; escape can mean host root |
| `--cap-add` / setcap | Grants Linux capabilities (e.g. SYS_ADMIN) on the host |
| `--network=host` | Container uses the host network stack |
| `--pid=host` | Container can see and signal host processes |
| seccomp/apparmor unconfined | Syscall and MAC confinement removed |
| `docker exec --privileged` | Escalates a running container after create |

Rootless docker rejects `--privileged` and limits host networking by default. There is no OPA or other daemon-level policy in this project.

Recreate the proxy alone:

```bash
./linux/docker-proxy.sh
curl -s http://127.0.0.1:2375/_ping
```

## Bootstrap files

| File | Description |
|------|-------------|
| `linux/config.fish` | Host fish helpers (`vibe`, `viberoot`, tool aliases). Installed by `linux/vibe.sh` |
| `shared/setup.sh` | Shared container bootstrap template, seeded once to `/opt/setup.sh` |

Run setup inside vibespace after first boot:

```bash
viberoot
bash /opt/setup.sh
```

## Windows 11

### Requirements

- Windows 11 with virtualization enabled
- Docker Desktop using its WSL 2 engine and **Linux containers** mode
- WSL 2 with WSLg enabled (installed by default with current Windows 11 WSL)
- Windows PowerShell 5.1+ or PowerShell 7+
- The workspace drive shared with Docker Desktop when drive sharing is not automatic

Run the prerequisite check from PowerShell:

```powershell
.\windows\vibe.cmd Doctor
```

If Windows blocks local scripts, run the command without changing the machine's
permanent execution policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\vibe.windows.ps1 Doctor
```

Create the environment and enter it:

```powershell
.\windows\vibe.cmd Setup
.\windows\vibe.cmd Shell
```

The same commands work from Command Prompt, without execution-policy setup:

```bat
windows\vibe.cmd Setup
windows\vibe.cmd Shell
```

`Setup` builds the image when needed, creates persistent named volumes, starts
a private filtered Docker proxy, mounts the current Windows directory at `/w`,
and connects Wayland, X11, and PulseAudio from WSLg. Linux GUI windows then open
directly on the Windows 11 desktop. It never exposes the Docker socket directly
to the development container.

### Windows commands

| Command | Purpose |
|---------|---------|
| `.\windows\vibe.cmd Doctor` | Validate PowerShell, Docker Desktop, WSLg, Linux container mode, and workspace |
| `.\windows\vibe.cmd Setup` | Create the environment and install any `opt/*.deb` packages |
| `.\windows\vibe.cmd Rebuild` | Rebuild the Ubuntu image and recreate the environment |
| `.\windows\vibe.cmd Start` | Start an existing environment |
| `.\windows\vibe.cmd Shell` | Enter Fish as the development user |
| `.\windows\vibe.cmd Root` | Enter Fish as root |
| `.\windows\vibe.cmd T3Code` | Open T3 Code entirely inside the container through WSLg |
| `.\windows\vibe.cmd Bootstrap` | Run the optional `/opt/setup.sh` installer |
| `.\windows\vibe.cmd Upgrade` | Upgrade Ubuntu packages |
| `.\windows\vibe.cmd Status` | Show Docker and Vibespace status |
| `.\windows\vibe.cmd Logs` | Show the latest container logs |
| `.\windows\vibe.cmd GuiTest` | Validate Wayland/X11/audio/OpenGL and open a test window |
| `.\windows\vibe.cmd Stop` | Stop Vibespace and its API proxy |
| `.\windows\vibe.cmd Cleanup` | Remove containers and the private network, preserving data |
| `.\windows\vibe.cmd Cleanup -PurgeData` | Also delete Vibespace volumes and its image |

Options such as `-Workspace`, `-ContainerName`, `-ImageName`, `-CpuLimit`,
`-Memory`, and `-WslDistribution` customize the environment. For example:

```powershell
.\windows\vibe.cmd Setup -Workspace C:\src -CpuLimit 8 -Memory 6g
```

When more than one WSL distribution is installed, automatic detection chooses
the first distribution with working WSLg sockets. Select one explicitly with:

```powershell
.\windows\vibe.cmd Setup -WslDistribution Ubuntu
```

The development home and `/opt` use Docker named volumes (`vibespace-home` and
`vibespace-opt`), so they survive recreation. The host workspace remains a
normal Windows directory. The project's `opt` folder is mounted separately at
`/packages` and is used only as the source for local Debian installers.

### Docker inside Vibespace on Windows

The image includes Docker CLI and Compose v2. `docker` and `docker compose`
inside Vibespace talk to a deny-by-default proxy on a private, non-published
network. Containers, images, networks, builds, and named volumes are supported.
Host bind mounts requested by inner Docker are blocked because `/w` exists in
the development container, not at the same path in Docker Desktop's Linux VM.
Use named volumes for databases and generated container data.

### GUI applications

GUI passthrough is enabled by default and is a required part of `Doctor` and
`Setup`. The launcher finds a WSL 2 distribution with WSLg, mounts its Wayland,
X11, and PulseAudio sockets read-only (including the conventional
`/tmp/.X11-unix` X11 path), and configures GTK, Qt, SDL, Mozilla, and Electron
applications. Test the complete path after setup:

```powershell
.\windows\vibe.cmd GuiTest
```

`GuiTest` checks all sockets and the OpenGL renderer, then opens `glxgears` on
the Windows desktop. Close that window to finish the command. Docker Desktop
does not currently pass WSL's `/dev/dxg` device into ordinary containers, so
GUI rendering may use software acceleration; application windows and audio
still work through WSLg.

For a deliberately terminal-only installation, add `-NoGui` consistently to
`Doctor`, `Setup`, and `Status`. This is an opt-out; the default Windows 11
configuration treats GUI support as mandatory.

### Included development applications

After `Setup` or `Rebuild`, these commands are immediately available inside
`Shell`:

```bash
code /w
codex
t3
mise current
node --version
npm --version
go version
```

VS Code opens through WSLg on the Windows desktop. Node uses mise's moving
`lts` channel and Go uses `latest`; `Rebuild` resolves the newest versions
available at build time. Codex stores its login and settings in `~/.codex`,
inside the persistent `vibespace-home` volume. The `code` wrapper disables
Chromium's namespace sandbox because Docker Desktop does not permit that nested
sandbox; the Vibespace container remains the outer isolation boundary.

### T3 Code on Windows 11

The shared image installs the official `t3` npm package and the Falkon Linux
browser. There is no native Windows T3 installation and no `winget` step.
Start it with:

```powershell
.\windows\vibe.cmd T3Code
```

The T3 server and browser both run as the normal `developer` user inside
Vibespace. WSLg displays the Linux browser window on the Windows desktop. Close
the window to stop the T3 server. Projects, Codex sessions, credentials, and
files remain inside the container and its persistent home volume.

On Linux, use `./linux/t3-code.sh`. T3 Code requires an authenticated provider;
for the included Codex CLI, run `codex login` once in `Shell` first.

### Installing local .deb applications

Create or use the `opt` folder at the repository root, copy one or more
`.deb` files into it, then run:

```powershell
.\windows\vibe.cmd Setup
# or, to rebuild the image too:
.\windows\vibe.cmd Rebuild
```

Every `opt/*.deb` file is installed into the Ubuntu container with `apt`, so
dependencies are resolved automatically. The folder is mounted read-only at
`/packages`; package files remain on the host and are ignored by Git. A T3
`.deb` is not needed because T3 is already part of the image.

## Container fish config

Suggested `~/.config/fish/conf.d/vibespace.fish` **inside** the container:

```fish
set fish_greeting
eval (~/.local/bin/mise activate fish)
export ELECTRON_OZONE_PLATFORM_HINT=wayland
export XDG_SESSION_TYPE=wayland
alias antigravity="/bin/antigravity --ozone-platform=wayland"
```
