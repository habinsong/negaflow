[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Architecture = 'x64',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    # 이미 만들어 둔 레이아웃을 그대로 다시 등록해 띄운다. 코드를 고치지 않았을 때만 쓴다.
    [switch]$SkipBuild,

    # 느슨한 설치 payload에서만 preview trace를 켠다. 만든 MSIX에는 이 marker가 들어가지 않는다.
    [switch]$EnablePreviewTrace,

    # 등록만 풀고 끝낸다. 설치본으로 넘어가기 전에 개발용 등록을 치우는 용도다.
    [switch]$Unregister,

    [int]$RegisterTimeoutSeconds = 180
)

# 앱을 띄우는 유일한 입구다.
#
# Negaflow.Shell 은 `WindowsPackageType=MSIX` 로 빌드된다. 그래서 빌드 폴더의 느슨한 exe 는
# 실행되지 않는다 — apphost 가 런타임을 앱 폴더에서만 찾도록 박혀 있어 "You must install or
# update .NET to run this application" 으로 끝난다. 손으로 자체 포함 publish 를 하나 더 만들면
# 그 순간만 뜨고, 그것은 배포되는 물건이 아니라 확인의 값어치가 없다.
#
# 그래서 여기서는 배포와 같은 길을 간다: 패키지 MSIX 를 만들고, 풀고, 현재 사용자에게
# 등록하고, AUMID 로 띄운다. scripts/build-release.ps1 이 설치본을 만들 때 쓰는 것과 같은
# 단계이며 NSIS 만 빠져 있다.

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
$packageName = 'Negaflow.Windows'
$runtimeIdentifier = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$nativePreset = "$($Architecture.ToLowerInvariant())-$($Configuration.ToLowerInvariant())"
$layoutRoot = Join-Path $projectRoot "out\run\$runtimeIdentifier-$($Configuration.ToLowerInvariant())"
$payloadDirectory = Join-Path $layoutRoot 'payload'
$packageDirectory = Join-Path $layoutRoot 'msix'
$shellProject = Join-Path $projectRoot 'src\Shell\Negaflow.Shell.csproj'

# 버전은 저장소에 하나뿐이다 - `negaflow-mac\Sources\Chromabase\ProductVersion.txt`.
# 설치본(`build-release.ps1`)은 그 값을 manifest 의 Identity 에 박는데 개발 실행에는 그
# 단계가 없어서, 저장소의 `Package.appxmanifest` 에 적힌 자리표시자 `1.0.0.0` 을 그대로
# 달고 떴다. 앱 정보 창은 `Package.Current.Id.Version` 을 읽으므로 실제와 다른 값을
# 보여 준다. 두 길이 같은 자리에서 같은 값을 쓰게 한다.
function Resolve-ProductVersion {
    $versionFile = Join-Path $repositoryRoot 'negaflow-mac\Sources\Chromabase\ProductVersion.txt'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw "Product version file is missing: $versionFile"
    }
    $value = (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
    if ($value -notmatch '^\d+\.\d+\.\d+$') {
        throw "Product version '$value' must be x.y.z."
    }
    return $value
}

function Set-ManifestVersion {
    param([string]$Path, [string]$ProductVersion)
    [xml]$manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $namespace = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('appx', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $identity = $manifest.SelectSingleNode('/appx:Package/appx:Identity', $namespace)
    if ($null -eq $identity) {
        throw "Packaged manifest has no Identity: $Path"
    }
    $identity.SetAttribute('Version', "$ProductVersion.0")
    $manifest.Save($Path)
}

function Remove-Registration {
    $installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
    if ($null -eq $installed) {
        return $false
    }
    foreach ($package in $installed) {
        Write-Host "[run-app] removing $($package.PackageFullName)" -ForegroundColor DarkGray
        Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
    }
    return $true
}

if ($Unregister) {
    if (Remove-Registration) { Write-Host '[run-app] unregistered' -ForegroundColor Green }
    else { Write-Host '[run-app] nothing was registered' -ForegroundColor Yellow }
    return
}

# 앞서 띄워 둔 앱은 payload 폴더의 파일(clrjit.dll 등)을 잠그고 있다. 그 상태로 payload 를
# 지우면 Remove-Item 이 UnauthorizedAccessException 으로 죽는다. 뒤에서 Add-AppxPackage
# -ForceApplicationShutdown 이 하는 일을 payload 를 다시 풀기 전으로 당긴다.
function Stop-PayloadProcesses {
    $running = @()
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        $path = try { $process.Path } catch { $null }
        if ($path -and $path.StartsWith($payloadDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            $running += $process
        }
    }
    foreach ($process in $running) {
        Write-Host "[run-app] stopping $($process.ProcessName) ($($process.Id)) - it is running from the payload" -ForegroundColor DarkGray
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $null = $process.WaitForExit(10000)
    }
}

# makeappx 는 Windows SDK 와 함께 온다. 여러 SDK 가 깔려 있으면 가장 높은 버전을 쓴다.
function Resolve-MakeAppx {
    $command = Get-Command makeappx -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $architectureFolder = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $binRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
    if (Test-Path -LiteralPath $binRoot) {
        $candidate = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^10\.' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName "$architectureFolder\makeappx.exe" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate
        }
    }
    throw 'makeappx.exe was not found. Install the Windows 10/11 SDK first.'
}

$productVersion = Resolve-ProductVersion

if (-not $SkipBuild) {
    Write-Host "[run-app] native: $nativePreset" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'build.ps1') -Preset $nativePreset
    if ($LASTEXITCODE -ne 0) {
        throw "Native build failed for '$nativePreset'."
    }

    Write-Host "[run-app] packaged build: $Architecture $Configuration" -ForegroundColor Cyan
    if (Test-Path -LiteralPath $packageDirectory) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    }
    # 자체 포함으로 만든다. 등록된 패키지 안에서는 공유 런타임을 찾지 않기 때문이다.
    & dotnet build $shellProject --configuration $Configuration --runtime $runtimeIdentifier `
        --self-contained true -p:Platform=$Architecture -p:Version=$productVersion `
        -p:WindowsAppSDKSelfContained=false `
        -p:WindowsPackageType=MSIX -p:EnableMsixTooling=true `
        -p:AppxPackageSigningEnabled=false -p:GenerateAppxPackageOnBuild=true `
        -p:AppxBundle=Never -p:UapAppxPackageBuildMode=SideloadOnly `
        -p:AppxPackageDir=$packageDirectory\
    if ($LASTEXITCODE -ne 0) {
        throw "Packaged build failed for '$runtimeIdentifier'."
    }

    # Dependencies\ 아래에는 Windows App Runtime 프레임워크 패키지가 함께 놓인다. 앱
    # 패키지만 골라야 하므로 그 하위 폴더는 제외한다.
    $appPackages = @(Get-ChildItem -LiteralPath $packageDirectory -Recurse -Filter '*.msix' -File |
        Where-Object { $_.FullName -notmatch '\\Dependencies\\' })
    if ($appPackages.Count -ne 1) {
        throw "Expected exactly one application MSIX in '$packageDirectory' but found $($appPackages.Count)."
    }

    if (Test-Path -LiteralPath $payloadDirectory) {
        Stop-PayloadProcesses
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
    & (Resolve-MakeAppx) unpack /p $appPackages[0].FullName /d $payloadDirectory /o /nv
    if ($LASTEXITCODE -ne 0) {
        throw "Could not unpack the application MSIX: $($appPackages[0].FullName)"
    }
    # 블록 맵은 압축된 패키지의 무결성 목록이라 느슨한 레이아웃 등록에는 쓰이지 않는다.
    $blockMap = Join-Path $payloadDirectory 'AppxBlockMap.xml'
    if (Test-Path -LiteralPath $blockMap) {
        Remove-Item -LiteralPath $blockMap -Force
    }
}

$manifestPath = Join-Path $payloadDirectory 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Package manifest is missing: $manifestPath. Run without -SkipBuild first."
}

# 설치본과 같은 버전을 답니다. 이것이 없으면 앱 정보 창이 `1.0.0.0` 을 보여 줍니다.
Set-ManifestVersion -Path $manifestPath -ProductVersion $productVersion
Write-Host "[run-app] version $productVersion.0" -ForegroundColor DarkGray

$previewTraceMarker = Join-Path $payloadDirectory 'preview-trace.on'
if ($EnablePreviewTrace) {
    $null = New-Item -ItemType File -Path $previewTraceMarker -Force
} elseif (Test-Path -LiteralPath $previewTraceMarker -PathType Leaf) {
    Remove-Item -LiteralPath $previewTraceMarker -Force
}

# 등록은 멈출 수 있는 단계다(CI 설치본 잡이 실제로 여기서 멈춘다). 어디서 멈췄는지 말하고
# 끝나도록 시간을 재고, 넘기면 그 사실을 알린다 — 조용히 매달려 있지 않는다.
Write-Host '[run-app] registering the loose package' -ForegroundColor Cyan
$null = Remove-Registration
$register = Start-Job -ScriptBlock {
    param($manifest)
    Add-AppxPackage -Register $manifest -ForceApplicationShutdown -ForceUpdateFromAnyVersion
} -ArgumentList $manifestPath
if (-not (Wait-Job -Job $register -Timeout $RegisterTimeoutSeconds)) {
    Stop-Job -Job $register
    Remove-Job -Job $register -Force
    throw "Add-AppxPackage -Register did not finish within $RegisterTimeoutSeconds seconds."
}
Receive-Job -Job $register
Remove-Job -Job $register -Force

$installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $installed) {
    throw 'The package registered without error but is not installed.'
}
$aumid = "$($installed.PackageFamilyName)!App"
Write-Host "[run-app] launching $aumid" -ForegroundColor Cyan
Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$aumid"
Write-Host '[run-app] started' -ForegroundColor Green
