[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallerPath,

    [string]$InstallDirectory,

    [ValidateRange(1, 60)]
    [int]$InstallTimeoutMinutes = 10
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

# 무인 설치는 payload 를 풀고 PowerShell 로 패키지를 등록한다. 그 등록이 멈추면 -Wait 는
# 영원히 돌아오지 않고, CI 에서는 잡이 취소될 때까지 아무 것도 남지 않는다(2026-08-17 관측:
# 25분 뒤 Negaflow-1.0.9-x64-setup 이 orphan 으로 종료됨). 기다림에 경계를 두어 멈춘 자리를
# 로그로 남긴다.
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
    try { $process.Kill($true) } catch { }
    throw "Silent install timed out after $($installTimeout.TotalMinutes) minute(s)."
}
if ($process.ExitCode -ne 0) {
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

$uninstaller = Join-Path $InstallDirectory 'uninstall.exe'
$process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Silent uninstall failed with exit code $($process.ExitCode)."
}
if (Test-Path -LiteralPath $InstallDirectory) {
    throw "Uninstaller left its application directory behind: $InstallDirectory"
}
if ($null -ne (Get-AppxPackage -Name 'Negaflow.Windows' -ErrorAction SilentlyContinue)) {
    throw 'Uninstaller left the Negaflow.Windows package identity registered.'
}

Write-Host "Installer install, package registration, window launch, and uninstall passed: $InstallerPath" -ForegroundColor Green
