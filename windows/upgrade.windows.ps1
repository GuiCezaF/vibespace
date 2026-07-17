# Backward-compatible wrapper. Prefer: .\vibe.windows.ps1 Upgrade
[CmdletBinding()]
param([string]$ContainerName = "vibespace")

& (Join-Path $PSScriptRoot "vibe.windows.ps1") Upgrade -ContainerName $ContainerName
exit $LASTEXITCODE
