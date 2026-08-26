[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Register', 'Unregister')]
    [string]$Action,

    [string]$ManifestPath,

    # 등록이 멈추면 설치 프로그램이 그대로 매달립니다. CI 는 그것을 25 분 뒤 orphan 으로
    # 끝내고, 어디서 멈췄는지는 아무 데도 남지 않습니다.
    # 설치 프로그램은 등록을 한 번 더 시도합니다. 상한이 크면 그 두 번이 그대로 잡 시간을
    # 먹으므로, 한 번에 3 분을 넘기지 않게 둡니다 - 정상 등록은 실측으로 수 초입니다.
    [ValidateRange(30, 1800)]
    [int]$RegisterTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$packageName = 'Negaflow.Windows'

if ($Action -eq 'Unregister') {
    Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction Stop
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw 'ManifestPath is required for package registration.'
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Package manifest does not exist: $ManifestPath"
}

# **등록은 멈출 수 있는 단계입니다.**
#
# `scripts/run-app.ps1` 이 같은 자리에 이미 시간을 재고 있고, 그 주석은 "CI 설치본 잡이 실제로
# 여기서 멈춘다" 고 적고 있습니다. 설치 프로그램이 부르는 이 길에는 그 경계가 없어서, 멈추면
# 무인 설치가 끝나지 않고 CI 는 10 분 뒤 시간 초과로만 끝납니다 - 무엇이 멈췄는지는 남지
# 않습니다.
#
# 시간을 재고, 넘기면 그 사실과 그때의 상태를 남긴 뒤 실패로 끝냅니다. 조용히 매달려 있지
# 않습니다.
$register = Start-Job -ScriptBlock {
    param($manifest)
    Add-AppxPackage -Register $manifest -ForceApplicationShutdown -ForceUpdateFromAnyVersion
} -ArgumentList $ManifestPath
if (-not (Wait-Job -Job $register -Timeout $RegisterTimeoutSeconds)) {
    Write-Host "Add-AppxPackage -Register did not finish within $RegisterTimeoutSeconds seconds."
    Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
        Format-List Name, PackageFullName, Status, InstallLocation |
        Out-String |
        Write-Host
    Get-Service -Name 'AppXSvc', 'ClipSVC' -ErrorAction SilentlyContinue |
        Format-Table -AutoSize Name, Status |
        Out-String |
        Write-Host
    Stop-Job -Job $register
    Remove-Job -Job $register -Force
    throw "Add-AppxPackage -Register did not finish within $RegisterTimeoutSeconds seconds."
}
Receive-Job -Job $register
Remove-Job -Job $register -Force
