[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,

    [string]$InstallDirectory,

    [ValidateRange(1, 60)]
    [int]$InstallTimeoutMinutes = 10,

    [ValidateRange(1, 30)]
    [int]$UninstallTimeoutMinutes = 3
)

$ErrorActionPreference = 'Stop'
$InstallerPath = [System.IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Installer does not exist: $InstallerPath"
}

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('negaflow-installer-' + [Guid]::NewGuid().ToString('N'))
}
$InstallDirectory = [System.IO.Path]::GetFullPath($InstallDirectory)
if (Test-Path -LiteralPath $InstallDirectory) {
    throw "Verification install directory must not already exist: $InstallDirectory"
}

# 패키지 신원 `Negaflow.Windows` 는 계정에 하나뿐이다. 이 검증은 임시 폴더에 설치하지만
# 그 신원과 시작 메뉴 바로가기는 전역이라, 실기에 이미 설치돼 있던 negaflow 가 검증 한 번에
# 등록이 풀리고 바로가기까지 사라진다 - 2026-08-26 이 기계에서 실제로 그렇게 지워졌다.
# CI 러너에는 설치가 없어 드러나지 않던 자리다. 있던 설치를 기억해 두었다가 끝나면 같은
# 설치 관리자로 되돌린다. 되돌리는 방법을 여기서 흉내내지 않고 설치 관리자에게 맡긴다.
$priorInstallLocation = $null
$priorPackage = Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue
if ($null -ne $priorPackage -and -not [string]::IsNullOrWhiteSpace($priorPackage.InstallLocation)) {
    $priorInstallLocation = [System.IO.Path]::GetFullPath($priorPackage.InstallLocation)
    Write-Host "Existing installation will be restored afterwards: $priorInstallLocation"
}

function Restore-PriorInstallation {
    if ($null -eq $script:priorInstallLocation) {
        return
    }
    if ($null -ne (Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue)) {
        return
    }
    Write-Host "Restoring the previous installation: $script:priorInstallLocation"
    $restore = Start-Process -FilePath $InstallerPath -ArgumentList @('/S', "/D=$script:priorInstallLocation") -PassThru
    if (-not $restore.WaitForExit(600000)) {
        try { $restore.Kill($true) } catch { }
        Write-Host 'WARNING: restoring the previous installation timed out.'
        return
    }
    if ($restore.ExitCode -ne 0) {
        Write-Host "WARNING: restoring the previous installation failed with exit code $($restore.ExitCode)."
    }
}

# 검증이 도중에 터져도 되돌린다.
trap { Restore-PriorInstallation; break }

# 무인 설치는 payload 를 풀고 PowerShell 로 패키지를 등록한다. 그 등록이 멈추면 -Wait 는
# 영원히 돌아오지 않고, CI 에서는 잡이 취소될 때까지 아무 것도 남지 않는다(2026-08-17 관측:
# 25분 뒤 Negaflow-1.0.9-x64-setup 이 orphan 으로 종료됨). 기다림에 경계를 두어 멈춘 자리를
# 로그로 남긴다.

# 설치 프로그램이 남긴 등록 기록. NSIS 는 플러그인 출력을 레지스터에만 담아 두고 무인
# 설치에는 그것을 보여 줄 화면이 없어, 여태 실패 이유가 통째로 사라졌습니다.
function Write-RegistrationLog {
    $log = Join-Path ([System.IO.Path]::GetTempPath()) 'negaflow-install-registration.log'
    if (-not (Test-Path -LiteralPath $log)) {
        Write-Host "No registration log at $log (설치가 등록 단계에 닿지 못했습니다)."
        return
    }
    Write-Host "--- $log ---"
    Get-Content -LiteralPath $log -Encoding UTF8 | Write-Host
    Write-Host '--- end ---'
}
# 서명 없는 느슨한 패키지를 등록하는 길은 기계의 잠금 해제 상태에 달려 있다. 개발 기계는
# 개발자 모드가 켜져 있어 늘 되고, 그것이 켜져 있는 한 "여기서는 되더라" 는 사용자 PC 에
# 대해 아무것도 증명하지 않는다. 어떤 기계에서 통과한 것인지 결과와 함께 남긴다.
$unlock = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
Write-Host ("AppModelUnlock: AllowDevelopmentWithoutDevLicense=" +
    "$(if ($null -ne $unlock) { $unlock.AllowDevelopmentWithoutDevLicense } else { '<none>' })" +
    " AllowAllTrustedApps=$(if ($null -ne $unlock) { $unlock.AllowAllTrustedApps } else { '<none>' })")

$installTimeout = [TimeSpan]::FromMinutes($InstallTimeoutMinutes)
$process = Start-Process -FilePath $InstallerPath -ArgumentList @('/S', "/D=$InstallDirectory") -PassThru
if (-not $process.WaitForExit($installTimeout.TotalMilliseconds)) {
    Write-Host "Silent install did not finish within $($installTimeout.TotalMinutes) minute(s)."
    Write-Host 'Processes still running:'
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match 'Negaflow|powershell|makeappx|AppxDeployment' } |
        Format-Table -AutoSize Id, ProcessName, StartTime |
        Out-String |
        Write-Host
    Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue |
        Format-List Name, PackageFullName, Status |
        Out-String |
        Write-Host
    Write-RegistrationLog
    try { $process.Kill($true) } catch { }
    throw "Silent install timed out after $($installTimeout.TotalMinutes) minute(s)."
}
if ($process.ExitCode -ne 0) {
    Write-RegistrationLog
    throw "Silent install failed with exit code $($process.ExitCode)."
}

foreach ($required in @(
    'Negaflow.Shell.exe',
    'Negaflow.Native.dll',
    'resources.pri',
    'AppxManifest.xml',
    'Assets\Negaflow.ico',
    'hostfxr.dll',
    'coreclr.dll',
    'Microsoft.WindowsAppRuntime.Bootstrap.dll',
    'package-registration.ps1',
    'uninstall.exe'
)) {
    $path = Join-Path $InstallDirectory $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Installed payload is missing '$required': $path"
    }
}

$package = Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue
if ($null -eq $package) {
    throw 'Installer did not register the Negaflow.Windows package identity.'
}
if (-not [string]::Equals(
    [System.IO.Path]::GetFullPath($package.InstallLocation),
    $InstallDirectory,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw "Registered package points at '$($package.InstallLocation)', expected '$InstallDirectory'."
}

$installedExecutable = Join-Path $InstallDirectory 'Negaflow.Shell.exe'
Start-Process -FilePath "$env:WINDIR\explorer.exe" `
    -ArgumentList 'shell:AppsFolder\Negaflow.Windows_esnvpjf0wq370!App'
$deadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    Start-Sleep -Milliseconds 100
    $applicationProcess = Get-Process -Name 'Negaflow.Shell' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                [string]::Equals($_.Path, $installedExecutable, [StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $false
            }
        } |
        Select-Object -First 1
    if ($null -ne $applicationProcess) {
        $applicationProcess.Refresh()
    }
} while (($null -eq $applicationProcess -or $applicationProcess.MainWindowHandle -eq 0) -and
    [DateTime]::UtcNow -lt $deadline)

if ($null -eq $applicationProcess -or $applicationProcess.MainWindowHandle -eq 0) {
    throw 'Installed package did not expose a Negaflow window within 15 seconds.'
}
Stop-Process -Id $applicationProcess.Id -Force
$applicationProcess.WaitForExit(5000) | Out-Null

# NSIS 제거기는 제 디렉터리째 지워야 해서, 실행되면 스스로를 $TEMP 로 복사하고 그 복사본에
# 일을 넘긴 뒤 **원본은 즉시 0 으로 빠집니다**. `-Wait` 가 기다리는 것은 그 원본이라 실제
# 제거가 끝나기 전에 다음 줄로 넘어갑니다 - 2026-08-26 관측: 여기서 "디렉터리가 남았다"로
# 실패했는데 같은 디렉터리가 잠시 뒤 스스로 사라져 있었습니다. 끝난 자리를 결과로 기다립니다.
$uninstaller = Join-Path $InstallDirectory 'uninstall.exe'
$process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -PassThru
if (-not $process.WaitForExit(60000)) {
    try { $process.Kill($true) } catch { }
    throw 'Silent uninstall did not hand off to its worker copy within 1 minute.'
}
if ($process.ExitCode -ne 0) {
    throw "Silent uninstall failed with exit code $($process.ExitCode)."
}

$uninstallDeadline = [DateTime]::UtcNow.AddMinutes($UninstallTimeoutMinutes)
do {
    $directoryRemains = Test-Path -LiteralPath $InstallDirectory
    $packageRemains = $null -ne (Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue)
    if (-not $directoryRemains -and -not $packageRemains) {
        break
    }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $uninstallDeadline)

if ($directoryRemains -or $packageRemains) {
    Write-Host 'Processes still running:'
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match 'Au_|Negaflow|powershell|AppxDeployment' } |
        Format-Table -AutoSize Id, ProcessName, StartTime |
        Out-String |
        Write-Host
}
if ($directoryRemains) {
    throw "Uninstaller left its application directory behind: $InstallDirectory"
}
if ($packageRemains) {
    throw 'Uninstaller left the Negaflow.Windows package identity registered.'
}

Write-Host "Installer install, package registration, window launch, and uninstall passed: $InstallerPath" -ForegroundColor Green

Restore-PriorInstallation
