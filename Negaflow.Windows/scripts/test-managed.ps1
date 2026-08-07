[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release')]
    [string]$Preset = 'x64-debug'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
# Shell.UnitTests 는 Shell.Core 를 거쳐 Interop 을 참조하므로 아키텍처가 고정돼 있다.
# 여기서 AnyCPU 로 강제하면 방금 빌드한 것이 아니라 예전 출력이 돌아 조용히 통과한다.
$testProjects = @(
    @{ Path = 'tests\Catalog.UnitTests\Negaflow.Catalog.UnitTests.csproj'; Platform = 'AnyCPU' },
    @{ Path = 'tests\Shell.UnitTests\Negaflow.Shell.UnitTests.csproj'; Platform = 'x64' }
)

& (Join-Path $PSScriptRoot 'build-managed.ps1') -Preset $Preset
if ($LASTEXITCODE -ne 0) {
    throw "Managed build failed for preset '$Preset'."
}

Push-Location $projectRoot
try {
    foreach ($testProject in $testProjects) {
        & dotnet run --project $testProject.Path --configuration $configuration `
            -p:Platform=$($testProject.Platform) --no-build --no-restore
        if ($LASTEXITCODE -ne 0) {
            throw "Managed unit tests failed for '$($testProject.Path)'."
        }
    }
}
finally {
    Pop-Location
}
