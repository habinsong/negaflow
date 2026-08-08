[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release', 'arm64-debug', 'arm64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    & cmake --preset $Preset
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configure failed for preset '$Preset'."
    }

    & cmake --build --preset $Preset
    if ($LASTEXITCODE -ne 0) {
        throw "CMake build failed for preset '$Preset'."
    }
}
finally {
    Pop-Location
}
