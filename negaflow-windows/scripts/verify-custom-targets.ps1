[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release')]
    [string]$Preset = 'x64-release'
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'WinUI, fxc, Direct3D 검증은 Windows에서 실행해야 합니다.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
Push-Location $projectRoot
try {
    & (Join-Path $PSScriptRoot 'build.ps1') -Preset $Preset
    & (Join-Path $PSScriptRoot 'build-managed.ps1') -Preset $Preset
    $nativeRoot = Join-Path $projectRoot "out/build/native/$Preset"
    $report = Join-Path $nativeRoot 'custom-target-ctest.xml'
    & ctest --test-dir $nativeRoot -C $configuration `
        -R 'native\.(custom_color_target|gpu_custom_color_target)$' `
        --output-on-failure --output-junit $report
    if ($LASTEXITCODE -ne 0) { throw 'Custom CPU/Direct3D 검사가 실패했습니다.' }
    [xml]$results = Get-Content -Raw $report
    $gpu = $results.SelectSingleNode("//testcase[@name='native.gpu_custom_color_target']")
    if ($null -eq $gpu -or $null -ne $gpu.SelectSingleNode('skipped')) {
        throw 'Direct3D 검사가 실행되지 않았습니다. 생략을 성공으로 처리하지 않습니다.'
    }
    & dotnet run --project tests/Catalog.UnitTests/Negaflow.Catalog.UnitTests.csproj `
        --configuration $configuration -p:Platform=AnyCPU -- --custom-targets-only
    if ($LASTEXITCODE -ne 0) { throw 'Custom 카탈로그 검사가 실패했습니다.' }
    & dotnet run --project tests/Shell.UnitTests/Negaflow.Shell.UnitTests.csproj `
        --configuration $configuration -p:Platform=x64 --no-build --no-restore -- --custom-targets-only
    if ($LASTEXITCODE -ne 0) { throw 'Custom 선택·요청·문자열 검사가 실패했습니다.' }
    Write-Output 'Custom CPU/Direct3D, 카탈로그, 선택 계약 및 WinUI 빌드 검사 완료. 실제 UI 조작 검사는 별도입니다.'
}
finally { Pop-Location }
