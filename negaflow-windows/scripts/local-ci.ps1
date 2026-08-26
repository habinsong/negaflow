[CmdletBinding()]
param(
    [switch]$IncludeArm64Cross
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
$logDirectory = Join-Path $projectRoot 'out\logs'
$logPath = Join-Path $logDirectory ("local-ci-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$versionPath = Join-Path $repositoryRoot 'negaflow-mac\Sources\Chromabase\ProductVersion.txt'

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
Start-Transcript -LiteralPath $logPath -Force | Out-Null
try {
    Write-Host '[local-ci] core x64 release gate' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'ci-gate.ps1') -Preset x64-release `
        -IncludeArm64Cross:$IncludeArm64Cross

    Write-Host '[local-ci] build current setup' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build-release.ps1') -Architecture x64 `
        -SkipNativeBuild -Overwrite

    $version = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    $installer = Join-Path $projectRoot "out\release\win-x64\negaflow-$version-x64-setup.exe"
    Write-Host '[local-ci] install, package identity, window launch, uninstall' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'verify-installer.ps1') -InstallerPath $installer

    Write-Host '[local-ci] complete' -ForegroundColor Green
}
finally {
    Stop-Transcript | Out-Null
    Write-Host "[local-ci] log: $logPath"
}
