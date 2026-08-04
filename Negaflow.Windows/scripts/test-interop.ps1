[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
$nativeConfiguration = $configuration
$nativeDll = Join-Path $projectRoot "out\build\native\$Preset\$nativeConfiguration\Negaflow.Native.dll"
$testProject = Join-Path $projectRoot 'tests\Interop.ContractTests\Negaflow.Interop.ContractTests.csproj'

& (Join-Path $PSScriptRoot 'build.ps1') -Preset $Preset
if ($LASTEXITCODE -ne 0) {
    throw "Native build failed for preset '$Preset'."
}

& (Join-Path $PSScriptRoot 'build-managed.ps1') -Preset $Preset
if ($LASTEXITCODE -ne 0) {
    throw "Managed build failed for preset '$Preset'."
}

Push-Location $projectRoot
try {
    & dotnet run --project $testProject --configuration $configuration `
        -p:Platform=x64 --no-build --no-restore -- $nativeDll
    if ($LASTEXITCODE -ne 0) {
        throw "Interop contract tests failed for preset '$Preset'."
    }
}
finally {
    Pop-Location
}
