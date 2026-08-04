[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
$testProjects = @(
    'tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj',
    'tests\Shell.UnitTests\Negaflow.Shell.UnitTests.csproj'
)

& (Join-Path $PSScriptRoot 'build-managed.ps1') -Preset $Preset
if ($LASTEXITCODE -ne 0) {
    throw "Managed build failed for preset '$Preset'."
}

Push-Location $projectRoot
try {
    foreach ($testProject in $testProjects) {
        & dotnet run --project $testProject --configuration $configuration `
            -p:Platform=AnyCPU --no-build --no-restore
        if ($LASTEXITCODE -ne 0) {
            throw "Managed unit tests failed for '$testProject'."
        }
    }
}
finally {
    Pop-Location
}
