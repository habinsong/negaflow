[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release', 'arm64-debug', 'arm64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot 'build.ps1') -Preset $Preset
if ($LASTEXITCODE -ne 0) {
    throw "Build failed for preset '$Preset'."
}
Push-Location $projectRoot
try {
    & ctest --preset $Preset
    if ($LASTEXITCODE -ne 0) {
        throw "CTest failed for preset '$Preset'."
    }
}
finally {
    Pop-Location
}
