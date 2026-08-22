[CmdletBinding()]
param(
    [ValidateSet('x64-debug', 'x64-release')]
    [string]$Preset = 'x64-release',

    # ARM64 는 교차 빌드만 가능하고 x64 호스트에서 실행할 수 없다. GitHub 쪽에서도 main push
    # 에서만 도는 잡이라 로컬에서는 기본으로 끈다.
    [switch]$IncludeArm64Cross
)

# 로컬에서 Windows CI 와 같은 검사를 한 번에 돌리는 입구다.
# GitHub(.github/workflows/windows.yml)는 같은 단계를 나란한 잡으로 돌리므로 내용은 같고
# 순서만 다르다. macOS 쪽 짝은 저장소 루트의 negaflow-mac/scripts/ci-gate.sh 이며 서로 겹치지 않는다.
#
# 여기서 돌지 않는 것: provenance/라이선스 게이트는 macOS 잡이 negaflow-windows 경로까지
# 검사하므로 중복 실행하지 않는다. 직접 돌리려면 저장소 루트에서
#   py negaflow-mac/scripts/ci/verify-provenance.py

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configuration = if ($Preset.EndsWith('release')) { 'Release' } else { 'Debug' }
$managedPreset = $Preset

Push-Location $projectRoot
try {
    # AppResources.Get 로 부르는 키가 여섯 언어 resw 에 모두 있는지 먼저 봅니다.
    # 없는 키는 빌드를 통과하고 **실행 중에** InvalidOperationException 으로 창을 죽입니다 —
    # 2026-08-22 에 `libraryRemove` 하나로 파일 탭이 앱을 통째로 내렸습니다. 빌드보다 앞에
    # 두는 이유는 이것이 1 초도 안 걸리기 때문입니다.
    Write-Host '[windows-ci-gate] localized keys' -ForegroundColor Cyan
    & py -3 (Join-Path $PSScriptRoot 'check-localized-keys.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'Localized key gate failed - a key used in code is missing from Resources.resw.'
    }

    Write-Host "[windows-ci-gate] native: $Preset" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'test.ps1') -Preset $Preset
    if ($LASTEXITCODE -ne 0) {
        throw "Native gate failed for preset '$Preset'."
    }

    Write-Host "[windows-ci-gate] managed: $managedPreset" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'test-managed.ps1') -Preset $managedPreset
    if ($LASTEXITCODE -ne 0) {
        throw "Managed gate failed for preset '$managedPreset'."
    }

    if ($IncludeArm64Cross) {
        Write-Host "[windows-ci-gate] arm64 cross build only" -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot 'build.ps1') -Preset 'arm64-release'
        if ($LASTEXITCODE -ne 0) {
            throw 'ARM64 native cross build failed.'
        }
        & (Join-Path $PSScriptRoot 'build-managed.ps1') -Preset 'arm64-release'
        if ($LASTEXITCODE -ne 0) {
            throw 'ARM64 managed cross build failed.'
        }
        Write-Host '[windows-ci-gate] ARM64 built but not executed; not a runtime result.' -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}

Write-Host '[windows-ci-gate] complete' -ForegroundColor Green
