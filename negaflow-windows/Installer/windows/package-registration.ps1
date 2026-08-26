[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Register', 'Unregister', 'EnsureRuntime', 'EnableLoosePackageRegistration')]
    [string]$Action,

    [string]$ManifestPath,

    [string]$RuntimePackagePath,

    # 등록이 멈추면 설치 프로그램이 그대로 매달립니다. CI 는 그것을 25 분 뒤 orphan 으로
    # 끝내고, 어디서 멈췄는지는 아무 데도 남지 않습니다.
    # 설치 프로그램은 등록을 한 번 더 시도합니다. 상한이 크면 그 두 번이 그대로 잡 시간을
    # 먹으므로, 한 번에 3 분을 넘기지 않게 둡니다 - 정상 등록은 실측으로 수 초입니다.
    [ValidateRange(30, 1800)]
    [int]$RegisterTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$packageName = 'Negaflow.Windows'

# **패키지를 건드리는 일은 멈출 수 있는 단계입니다.**
#
# `scripts/run-app.ps1` 이 같은 자리에 이미 시간을 재고 있고, 그 주석은 "CI 설치본 잡이 실제로
# 여기서 멈춘다" 고 적고 있습니다. 설치 프로그램이 부르는 이 길에는 그 경계가 없어서, 멈추면
# 무인 설치가 끝나지 않고 CI 는 10 분 뒤 시간 초과로만 끝납니다 - 무엇이 멈췄는지는 남지
# 않습니다.
#
# 시간을 재고, 넘기면 그 사실과 그때의 상태를 남긴 뒤 실패로 끝냅니다. 조용히 매달려 있지
# 않습니다. 등록과 프레임워크 설치가 같은 위험을 나누므로 자리도 하나로 둡니다.
function Invoke-BoundedAppxOperation {
    param(
        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $job = Start-Job -ScriptBlock $Operation -ArgumentList $Arguments
    if (-not (Wait-Job -Job $job -Timeout $RegisterTimeoutSeconds)) {
        Write-Host "$Description did not finish within $RegisterTimeoutSeconds seconds."
        Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
            Format-List Name, PackageFullName, Status, InstallLocation |
            Out-String |
            Write-Host
        Get-Service -Name 'AppXSvc', 'ClipSVC' -ErrorAction SilentlyContinue |
            Format-Table -AutoSize Name, Status |
            Out-String |
            Write-Host
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        throw "$Description did not finish within $RegisterTimeoutSeconds seconds."
    }
    Receive-Job -Job $job
    Remove-Job -Job $job -Force
}

if ($Action -eq 'EnableLoosePackageRegistration') {
    # negaflow 는 서명하지 않은 **느슨한 패키지**로 등록됩니다(ADR-0027 이 코드 서명을 접었고,
    # 그래서 MSIX 가 아니라 NSIS + `Add-AppxPackage -Register` 입니다). Windows 는 그 등록을
    # `AllowDevelopmentWithoutDevLicense` 로 막아 두고, 깨끗한 PC 는 그 값이 없습니다.
    #
    # 개발 기계와 CI 러너는 둘 다 이 값이 1 이라 여태 드러나지 않았습니다 - 2026-08-26 CI
    # 로그에 러너 값을 찍어 확인했습니다. "여기서는 되더라" 가 사용자 PC 를 증명하지 못하는
    # 자리가 정확히 이것입니다.
    #
    # HKLM 이라 관리자가 필요합니다. 설치 자체는 사용자 영역 그대로 두고 이 한 단계만
    # 올립니다. 32 비트로 실행돼도 64 비트 하이브를 보도록 base key 를 직접 엽니다 —
    # 리디렉션된 Wow6432Node 에 써 두면 Windows 는 그것을 보지 않습니다.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Enabling loose-package registration requires administrator rights.'
    }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.CreateSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock', $true)
        try {
            $key.SetValue('AllowDevelopmentWithoutDevLicense', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            $written = $key.GetValue('AllowDevelopmentWithoutDevLicense')
        }
        finally { $key.Dispose() }
    }
    finally { $base.Dispose() }
    if ($written -ne 1) {
        throw "AllowDevelopmentWithoutDevLicense is '$written' after the write."
    }
    Write-Host 'AllowDevelopmentWithoutDevLicense=1 (loose-package registration is allowed).'
    exit 0
}

if ($Action -eq 'Unregister') {
    Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction Stop
    exit 0
}

if ($Action -eq 'EnsureRuntime') {
    # 앱 패키지는 Windows App Runtime 프레임워크에 기대고 있습니다. 그 프레임워크가 없는
    # 기계에서는 등록이 `0x80073CF3` 으로 거부되고, 설치 프로그램은 사용자 권한으로 도는지라
    # 나중에 깔아 줄 수도 없습니다 - 그래서 설치본이 프레임워크를 함께 싣고 먼저 갖춥니다.
    if ([string]::IsNullOrWhiteSpace($RuntimePackagePath)) {
        throw 'RuntimePackagePath is required to ensure the Windows App Runtime.'
    }
    $RuntimePackagePath = [System.IO.Path]::GetFullPath($RuntimePackagePath)
    if (-not (Test-Path -LiteralPath $RuntimePackagePath -PathType Leaf)) {
        throw "Windows App Runtime package does not exist: $RuntimePackagePath"
    }

    # 이름도 버전도 아키텍처도 패키지가 스스로 들고 있습니다. 여기에 숫자를 적어 두면 App SDK
    # 를 올릴 때마다 어긋나고, 어긋난 것은 프레임워크가 없는 기계에서만 드러납니다.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($RuntimePackagePath)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if ($null -eq $entry) {
            throw "Windows App Runtime package has no AppxManifest.xml: $RuntimePackagePath"
        }
        $stream = $entry.Open()
        try {
            $reader = New-Object System.IO.StreamReader($stream)
            try {
                [xml]$runtimeManifest = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }

    $runtimeIdentity = $runtimeManifest.Package.Identity
    $requiredVersion = [Version]$runtimeIdentity.Version
    $present = @(Get-AppxPackage -Name $runtimeIdentity.Name -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Architecture.ToString() -eq $runtimeIdentity.ProcessorArchitecture -and
            [Version]$_.Version -ge $requiredVersion
        })
    if ($present.Count -ne 0) {
        Write-Host "Windows App Runtime already present: $($present[0].PackageFullName)"
        exit 0
    }

    Write-Host ("Installing the bundled Windows App Runtime: " +
        "$($runtimeIdentity.Name) $($runtimeIdentity.Version) $($runtimeIdentity.ProcessorArchitecture)")
    Invoke-BoundedAppxOperation `
        -Description 'Add-AppxPackage (Windows App Runtime)' `
        -Operation {
            param($package)
            Add-AppxPackage -Path $package
        } `
        -Arguments @($RuntimePackagePath)
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw 'ManifestPath is required for package registration.'
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Package manifest does not exist: $ManifestPath"
}

Invoke-BoundedAppxOperation `
    -Description 'Add-AppxPackage -Register' `
    -Operation {
        param($manifest)
        Add-AppxPackage -Register $manifest -ForceApplicationShutdown -ForceUpdateFromAnyVersion
    } `
    -Arguments @($ManifestPath)
