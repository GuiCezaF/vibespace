# Vibespace lifecycle manager for Windows 11 + Docker Desktop.
[CmdletBinding()]
param(
    [ValidateSet("Setup", "Rebuild", "Start", "Shell", "Root", "Stop", "Status", "Logs", "GuiTest", "T3Code", "Bootstrap", "Upgrade", "Cleanup", "Doctor")]
    [string]$Action = "Setup",
    [string]$Workspace = (Get-Location).Path,
    [string]$ContainerName = "vibespace",
    [string]$ImageName = "vibespace:windows",
    [string]$ProxyImage = "docker.io/wollomatic/socket-proxy:1.12.2",
    [int]$CpuLimit = 6,
    [string]$Memory = "4g",
    [string]$WslDistribution = "",
    [switch]$NoGui,
    [switch]$PurgeData
)

$ErrorActionPreference = "Stop"
$ProxyName = "$ContainerName-docker-proxy"
$NetworkName = "$ContainerName-control"
$HomeVolume = "$ContainerName-home"
$OptVolume = "$ContainerName-opt"
$script:DockerCommand = $null
$script:WslgConfiguration = $null
$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
$SharedDir = Join-Path $ProjectRoot "shared"
$PackagesDir = Join-Path $ProjectRoot "opt"

function Write-Step([string]$Message) { Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Warning $Message }

function Require-Docker {
    $dockerApplication = Get-Command docker.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dockerApplication) {
        throw "Docker CLI not found. Install Docker Desktop for Windows and reopen PowerShell."
    }
    $script:DockerCommand = $dockerApplication.Source

    $null = & $script:DockerCommand version --format '{{.Server.Os}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop is not running. Start it and wait until the engine is ready."
    }

    $osType = (& $script:DockerCommand info --format '{{.OSType}}' 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $osType -ne "linux") {
        throw "Docker Desktop must be using Linux containers (current engine: '$osType')."
    }
}

function Invoke-Docker {
    [string[]]$Arguments = $args

    if ($Arguments -contains "-it") {
        & $script:DockerCommand @Arguments
    } else {
        $dockerOutput = & $script:DockerCommand @Arguments
        if ($null -ne $dockerOutput) { Write-Output $dockerOutput }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Arguments -join ' ')"
    }
}

function Test-Container([string]$Name) {
    $ErrorActionPreference = "SilentlyContinue"
    $null = & $script:DockerCommand container inspect $Name 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-Running([string]$Name) {
    $ErrorActionPreference = "SilentlyContinue"
    $state = & $script:DockerCommand container inspect --format '{{.State.Running}}' $Name 2>$null
    return $LASTEXITCODE -eq 0 -and $state -eq "true"
}

function Test-Image([string]$Name) {
    $ErrorActionPreference = "SilentlyContinue"
    $null = & $script:DockerCommand image inspect $Name 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-Network([string]$Name) {
    $ErrorActionPreference = "SilentlyContinue"
    $null = & $script:DockerCommand network inspect $Name 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-Volume([string]$Name) {
    $ErrorActionPreference = "SilentlyContinue"
    $null = & $script:DockerCommand volume inspect $Name 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-WorkspacePath {
    $resolved = (Resolve-Path -LiteralPath $Workspace).Path
    if ($resolved.Contains(',')) {
        throw "Workspace paths containing commas are not supported by Docker --mount: $resolved"
    }
    return $resolved
}

function Get-WslgConfiguration {
    if ($NoGui) { return $null }
    if ($null -ne $script:WslgConfiguration) { return $script:WslgConfiguration }

    $wslApplication = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wslApplication) {
        throw "WSL is required for Linux GUI applications. Install WSL with 'wsl --install', or use -NoGui for terminal-only mode."
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($WslDistribution)) {
        $candidates = @($WslDistribution)
    } else {
        $rawDistributions = & $wslApplication.Source --list --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            $candidates = @($rawDistributions | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
        }
    }

    foreach ($distribution in $candidates) {
        $null = & $wslApplication.Source --distribution $distribution --exec sh -lc `
            'test -S /mnt/wslg/runtime-dir/wayland-0 && test -S /mnt/wslg/.X11-unix/X0 && test -S /mnt/wslg/PulseServer' 2>$null
        if ($LASTEXITCODE -ne 0) { continue }

        $script:WslgConfiguration = [PSCustomObject]@{
            Distribution = $distribution
            HostPath = "\\wsl.localhost\$distribution\mnt\wslg"
            ContainerPath = "/mnt/wslg"
        }
        return $script:WslgConfiguration
    }

    $hint = if ($WslDistribution) { " in distribution '$WslDistribution'" } else { " in any installed WSL distribution" }
    throw "WSLg is not ready$hint. Run 'wsl --update', start a WSL 2 distribution, and run Setup again. Use -NoGui only for terminal-only mode."
}

function Get-GuiArguments {
    $wslg = Get-WslgConfiguration
    if ($null -eq $wslg) { return @() }

    return @(
        "--mount", "type=bind,source=$($wslg.HostPath),target=$($wslg.ContainerPath),readonly",
        "--mount", "type=bind,source=$($wslg.HostPath)\.X11-unix,target=/tmp/.X11-unix,readonly",
        "--mount", "type=bind,source=$($wslg.HostPath)\runtime-dir\wayland-0,target=/tmp/vibespace-runtime/wayland-0,readonly",
        "--env", "DISPLAY=:0",
        "--env", "WAYLAND_DISPLAY=wayland-0",
        "--env", "XDG_RUNTIME_DIR=/tmp/vibespace-runtime",
        "--env", "PULSE_SERVER=unix:/mnt/wslg/PulseServer",
        "--env", "ELECTRON_OZONE_PLATFORM_HINT=wayland",
        "--env", "MOZ_ENABLE_WAYLAND=1",
        "--env", "GDK_BACKEND=wayland,x11",
        "--env", "QT_QPA_PLATFORM=wayland",
        "--env", "SDL_VIDEODRIVER=wayland"
    )
}

function Test-ContainerGuiConfigured {
    if ($NoGui) { return $true }
    if (-not (Test-Container $ContainerName)) { return $false }

    $ErrorActionPreference = "SilentlyContinue"
    $destinations = @(& $script:DockerCommand container inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' $ContainerName 2>$null)
    return $LASTEXITCODE -eq 0 -and
        $destinations -contains "/mnt/wslg" -and
        $destinations -contains "/tmp/.X11-unix" -and
        $destinations -contains "/tmp/vibespace-runtime/wayland-0"
}

function Build-Image {
    Write-Step "Building Ubuntu development image: $ImageName"
    $toolchainRefresh = Get-Date -Format "yyyyMMddHHmmss"
    Invoke-Docker build `
        --build-arg USERID=1000 `
        --build-arg USERNAME=developer `
        --build-arg WORKSPACE=/w `
        --build-arg XDG_RUNTIME_DIR=/tmp/vibespace-runtime `
        --build-arg "TOOLCHAIN_REFRESH=$toolchainRefresh" `
        -f (Join-Path $SharedDir "Containerfile") `
        -t $ImageName $SharedDir
}

function Ensure-Storage {
    foreach ($volume in @($HomeVolume, $OptVolume)) {
        if (-not (Test-Volume $volume)) {
            Write-Step "Creating persistent volume: $volume"
            $null = Invoke-Docker volume create $volume
        }
    }
    if (-not (Test-Path -LiteralPath $PackagesDir -PathType Container)) {
        Write-Step "Creating local package folder: $PackagesDir"
        $null = New-Item -ItemType Directory -Path $PackagesDir -Force
    }
}

function Ensure-ControlNetwork {
    if (-not (Test-Network $NetworkName)) {
        Write-Step "Creating private Docker control network: $NetworkName"
        $null = Invoke-Docker network create --internal $NetworkName
    }
}

function Get-ProxyEnvironment {
    $allowGet = @(
        '/_ping', '/v1\.[0-9]+/version', '/v1\.[0-9]+/info',
        '/v1\.[0-9]+/containers/json', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/json',
        '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/logs', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/stats',
        '/v1\.[0-9]+/images/json', '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+/json',
        '/v1\.[0-9]+/networks', '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+',
        '/v1\.[0-9]+/volumes', '/v1\.[0-9]+/volumes/[a-zA-Z0-9_.-]+',
        '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/json'
    )
    $allowHead = @('/_ping')
    $allowPost = @(
        '/grpc', '/session',
        '/v1\.[0-9]+/containers/create', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/start',
        '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/attach', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/stop',
        '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/restart', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/kill',
        '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/wait', '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/exec',
        '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/start', '/v1\.[0-9]+/exec/[a-zA-Z0-9]+/resize',
        '/v1\.[0-9]+/images/create', '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+/tag', '/v1\.[0-9]+/build',
        '/v1\.[0-9]+/networks/create', '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+/connect',
        '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+/disconnect', '/v1\.[0-9]+/volumes/create'
    )
    $allowPut = @('/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+/archive')
    $allowDelete = @(
        '/v1\.[0-9]+/containers/[a-zA-Z0-9_.-]+', '/v1\.[0-9]+/images/[a-zA-Z0-9_.-]+',
        '/v1\.[0-9]+/networks/[a-zA-Z0-9_.-]+', '/v1\.[0-9]+/volumes/[a-zA-Z0-9_.-]+'
    )

    $environment = [System.Collections.Generic.List[string]]::new()
    $environment.AddRange([string[]]@(
        "SP_LISTENIP=0.0.0.0", "SP_PROXYPORT=2375", "SP_ALLOWFROM=0.0.0.0/0",
        "SP_SOCKETPATH=/var/run/docker.sock", "SP_ALLOWBINDMOUNTFROM=/__vibespace_bind_mounts_disabled__",
        "SP_LOGLEVEL=INFO"
    ))

    foreach ($entry in @(
        @{ Method = "GET"; Values = $allowGet }, @{ Method = "HEAD"; Values = $allowHead },
        @{ Method = "POST"; Values = $allowPost }, @{ Method = "PUT"; Values = $allowPut },
        @{ Method = "DELETE"; Values = $allowDelete }
    )) {
        for ($index = 0; $index -lt $entry.Values.Count; $index++) {
            $suffix = if ($index -eq 0) { "" } else { "_$($index + 1)" }
            $environment.Add("SP_ALLOW_$($entry.Method)$suffix=$($entry.Values[$index])")
        }
    }
    return $environment
}

function Recreate-Proxy {
    Ensure-ControlNetwork
    if (Test-Container $ProxyName) {
        $null = Invoke-Docker rm -f $ProxyName
    }

    Write-Step "Starting filtered Docker API proxy"
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.AddRange([string[]]@(
        "run", "-d", "--name", $ProxyName, "--user", "0:0", "--network", $NetworkName,
        "--mount", "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly"
    ))
    foreach ($variable in (Get-ProxyEnvironment)) {
        $arguments.Add("--env")
        $arguments.Add($variable)
    }
    $arguments.Add($ProxyImage)
    $null = Invoke-Docker @arguments
}

function Seed-SetupScript {
    & $script:DockerCommand exec $ContainerName test -f /opt/setup.sh 2>$null
    if ($LASTEXITCODE -eq 0) { return }

    Write-Step "Installing /opt/setup.sh into the persistent tools volume"
    Invoke-Docker cp (Join-Path $SharedDir "setup.sh") "${ContainerName}:/opt/setup.sh"
    Invoke-Docker exec -u root $ContainerName chmod 0700 /opt/setup.sh
}

function Install-LocalDebs {
    Write-Step "Checking local .deb packages in $PackagesDir"
    Invoke-Docker exec -u root $ContainerName vibe-install-debs /packages
}

function Create-Vibespace {
    $workspacePath = Get-WorkspacePath
    $guiArguments = Get-GuiArguments
    Ensure-Storage
    Recreate-Proxy

    if (Test-Container $ContainerName) {
        $null = Invoke-Docker rm -f $ContainerName
    }

    Write-Step "Creating Windows 11 Vibespace container"
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.AddRange([string[]]@(
        "create", "--name", $ContainerName, "--workdir", "/w", "--shm-size", "1g",
        "--cpus", "$CpuLimit", "--memory", $Memory,
        "--env", "DOCKER_HOST=tcp://${ProxyName}:2375",
        "--env", "VIBE_HOST_WORKSPACE=$workspacePath",
        "--mount", "type=bind,source=$workspacePath,target=/w",
        "--mount", "type=bind,source=$PackagesDir,target=/packages,readonly",
        "--mount", "type=volume,source=$HomeVolume,target=/home/developer",
        "--mount", "type=volume,source=$OptVolume,target=/opt"
    ))
    $arguments.AddRange([string[]]$guiArguments)
    $arguments.Add($ImageName)
    $null = Invoke-Docker @arguments

    Invoke-Docker network connect $NetworkName $ContainerName
    $null = Invoke-Docker start $ContainerName
    Seed-SetupScript
    Install-LocalDebs
    if (-not $NoGui) {
        $wslg = Get-WslgConfiguration
        Write-Ok "WSLg GUI enabled through distribution '$($wslg.Distribution)' (Wayland, X11, and audio)."
    }
    Write-Ok "Vibespace is ready. Enter with: .\windows\vibe.cmd Shell"
}

function Start-Vibespace {
    if (-not (Test-Container $ContainerName)) {
        throw "Container '$ContainerName' does not exist. Run .\windows\vibe.cmd Setup first."
    }
    if (-not $NoGui) {
        $null = Get-WslgConfiguration
        if (-not (Test-ContainerGuiConfigured)) {
            throw "Container '$ContainerName' was created without the complete WSLg mounts. Run .\windows\vibe.cmd Setup to enable GUI support."
        }
    }
    if (-not (Test-Running $ProxyName)) { Recreate-Proxy }
    if (-not (Test-Running $ContainerName)) { $null = Invoke-Docker start $ContainerName }
    Write-Ok "Vibespace is running."
}

function Show-Status {
    $desktopVersion = (& $script:DockerCommand version --format '{{.Server.Version}}').Trim()
    Write-Host "Docker engine: $desktopVersion (Linux containers)"
    foreach ($name in @($ContainerName, $ProxyName)) {
        if (Test-Container $name) {
            $state = (& $script:DockerCommand inspect --format '{{.State.Status}}' $name).Trim()
            Write-Host "$name`: $state"
        } else {
            Write-Host "$name`: not created"
        }
    }
    Write-Host "Workspace: $(Get-WorkspacePath) -> /w"
    Write-Host "Local packages: $PackagesDir -> /packages (read-only)"
    Write-Host "Persistent volumes: $HomeVolume, $OptVolume"
    if ($NoGui) {
        Write-Host "GUI: disabled by -NoGui"
    } else {
        try {
            $wslg = Get-WslgConfiguration
            $containerGui = if (Test-ContainerGuiConfigured) { "container configured" } else { "run Setup to configure container" }
            Write-Host "GUI: WSLg ready ($($wslg.Distribution), Wayland/X11/audio; $containerGui)"
        } catch {
            Write-Host "GUI: unavailable - $($_.Exception.Message)"
        }
    }
}

function Invoke-GuiTest {
    Start-Vibespace
    if ($NoGui) { throw "GuiTest cannot run with -NoGui." }

    Write-Step "Checking WSLg sockets and OpenGL renderer"
    Invoke-Docker exec $ContainerName sh -lc `
        'test -w "$XDG_RUNTIME_DIR" && test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" && test -S /mnt/wslg/.X11-unix/X0 && test -S /mnt/wslg/PulseServer && glxinfo -B'
    Write-Step "Opening glxgears. Close its Windows desktop window to finish the test."
    Invoke-Docker exec -it $ContainerName glxgears
}

function Invoke-T3Code {
    Start-Vibespace
    if ($NoGui) { throw "T3Code cannot run with -NoGui." }
    Write-Step "Opening T3 Code entirely inside Vibespace through WSLg"
    Invoke-Docker exec -it -w /w $ContainerName t3-code /w
}

function Invoke-Cleanup {
    Write-Step "Removing Vibespace containers and private network"
    foreach ($name in @($ContainerName, $ProxyName)) {
        if (Test-Container $name) { $null = Invoke-Docker rm -f $name }
    }
    if (Test-Network $NetworkName) { $null = Invoke-Docker network rm $NetworkName }

    if ($PurgeData) {
        Write-Warn "Purging persistent Vibespace volumes and image"
        foreach ($volume in @($HomeVolume, $OptVolume)) {
            if (Test-Volume $volume) { $null = Invoke-Docker volume rm $volume }
        }
        if (Test-Image $ImageName) { $null = Invoke-Docker image rm $ImageName }
    }
    Write-Ok "Cleanup finished. Persistent data was$(if ($PurgeData) { '' } else { ' not' }) removed."
}

function Invoke-Doctor {
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($PSVersionTable.PSVersion.Major -lt 5) { $problems.Add("PowerShell 5.1 or newer is required.") }
    $windowsBuild = 0
    try {
        $windowsBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    } catch {
        $problems.Add("Unable to determine the Windows build number.")
    }
    if ($windowsBuild -gt 0 -and $windowsBuild -lt 22000) {
        $problems.Add("Windows 11 is required (detected build: $windowsBuild).")
    }
    try { Require-Docker } catch { $problems.Add($_.Exception.Message) }
    if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { $problems.Add("Workspace does not exist: $Workspace") }
    if (-not $NoGui) {
        try { $null = Get-WslgConfiguration } catch { $problems.Add($_.Exception.Message) }
    }

    if ($problems.Count -gt 0) {
        foreach ($problem in $problems) { Write-Warn $problem }
        throw "Vibespace doctor found $($problems.Count) problem(s)."
    }
    Write-Ok "Windows 11 prerequisites look good$(if ($NoGui) { ' (terminal-only mode).' } else { ', including WSLg GUI.' })"
    Show-Status
}

if ($Action -eq "Doctor") {
    Invoke-Doctor
    return
}

Require-Docker

switch ($Action) {
    "Setup" {
        if (-not (Test-Image $ImageName)) { Build-Image }
        Create-Vibespace
    }
    "Rebuild" { Build-Image; Create-Vibespace }
    "Start" { Start-Vibespace }
    "Shell" { Start-Vibespace; Invoke-Docker exec -it -w /w $ContainerName fish }
    "Root" { Start-Vibespace; Invoke-Docker exec -u root -it -w /w $ContainerName fish }
    "Stop" {
        foreach ($name in @($ContainerName, $ProxyName)) {
            if (Test-Running $name) { $null = Invoke-Docker stop $name }
        }
        Write-Ok "Vibespace stopped."
    }
    "Status" { Show-Status }
    "Logs" { Invoke-Docker logs --tail 200 $ContainerName }
    "GuiTest" { Invoke-GuiTest }
    "T3Code" { Invoke-T3Code }
    "Bootstrap" { Start-Vibespace; Invoke-Docker exec -u root -it $ContainerName bash /opt/setup.sh }
    "Upgrade" {
        Start-Vibespace
        Invoke-Docker exec -u root $ContainerName fish -c 'apt update && apt full-upgrade -y && apt autoremove -y'
        Write-Ok "Upgrade finished."
    }
    "Cleanup" { Invoke-Cleanup }
}
