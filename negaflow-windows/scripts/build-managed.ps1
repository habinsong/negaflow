[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release', 'arm64-debug', 'arm64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$platform = if ($Preset.StartsWith('arm64')) { 'ARM64' } else { 'x64' }
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
$solution = Join-Path $projectRoot 'Negaflow.Windows.slnx'

Push-Location $projectRoot
try {
    & dotnet restore $solution --locked-mode -p:Platform=$platform
    if ($LASTEXITCODE -ne 0) {
        throw "Managed restore failed for preset '$Preset'."
    }

    & dotnet build $solution --configuration $configuration -p:Platform=$platform --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Managed build failed for preset '$Preset'."
    }
}
finally {
    Pop-Location
}
