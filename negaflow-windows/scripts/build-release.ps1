[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Architecture = 'x64',

    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$OutputDirectory,

    [switch]$SkipNativeBuild,

    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $projectRoot
$runtimeIdentifier = if ($Architecture -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$artifactArchitecture = $Architecture.ToLowerInvariant()
$nativePreset = if ($Architecture -eq 'ARM64') { 'arm64-release' } else { 'x64-release' }

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionFile = Join-Path $repositoryRoot 'negaflow-mac\Sources\Chromabase\ProductVersion.txt'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw "Release version file is missing: $versionFile. Pass -Version x.y.z explicitly."
    }
    $Version = (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Release version '$Version' must be x.y.z."
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot "out\release\$runtimeIdentifier"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$installerName = "Negaflow-$Version-$artifactArchitecture-setup.exe"
$installerPath = Join-Path $OutputDirectory $installerName
if ((Test-Path -LiteralPath $installerPath) -and -not $Overwrite) {
    throw "Installer already exists: $installerPath. Pass -Overwrite to replace this release artifact."
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

$makensis = Get-Command makensis -ErrorAction SilentlyContinue
if ($null -eq $makensis -and (Test-Path -LiteralPath 'C:\Program Files (x86)\NSIS\makensis.exe')) {
    $makensis = Get-Item -LiteralPath 'C:\Program Files (x86)\NSIS\makensis.exe'
}
if ($null -eq $makensis) {
    throw 'makensis was not found. Install NSIS first: winget install --id NSIS.NSIS --exact.'
}
$makensisPath = if ($makensis.PSObject.Properties.Name -contains 'Source') {
    $makensis.Source
}
else {
    $makensis.FullName
}

$payloadDirectory = Join-Path $OutputDirectory ('.payload-' + [Guid]::NewGuid().ToString('N'))
$packageDirectory = Join-Path $OutputDirectory ('.msix-' + [Guid]::NewGuid().ToString('N'))
$shellProject = Join-Path $projectRoot 'src\Shell\Negaflow.Shell.csproj'
$nativeLibrary = Join-Path $projectRoot "out\build\native\$nativePreset\Release\Negaflow.Native.dll"
$installerScript = Join-Path $projectRoot 'Installer\windows\negaflow.nsi'
$packageRegistrationScript = Join-Path $projectRoot 'Installer\windows\package-registration.ps1'

try {
    if (-not $SkipNativeBuild) {
        & (Join-Path $PSScriptRoot 'build.ps1') -Preset $nativePreset
        if ($LASTEXITCODE -ne 0) {
            throw "Native Release build failed for '$nativePreset'."
        }
    }
    if (-not (Test-Path -LiteralPath $nativeLibrary)) {
        throw "Native Release DLL is missing: $nativeLibrary"
    }

    # 설치본은 패키지 ID가 필요한 WinUI XAML을 사용하므로 unsigned loose package
    # 레이아웃을 만든다. NSIS가 파일을 배치하고 현재 사용자에게 manifest를 등록한다.
    #
    # 레이아웃은 빌드가 만든 unsigned MSIX를 풀어서 얻는다. `dotnet publish` 산출물에는
    # AppxManifest.xml 과 Assets\ 가 없고, 저장소의 Package.appxmanifest 는 아직
    # `$targetnametoken$`/`$targetentrypoint$` 토큰을 들고 있어 그대로 쓸 수 없다. MSIX 를
    # 만들어 푸는 경로만이 토큰이 해석된 manifest 를 손으로 짜맞추지 않고 얻는 길이다.
    & dotnet clean $shellProject --configuration Release -p:Platform=$Architecture `
        -p:WindowsPackageType=MSIX -p:EnableMsixTooling=true --verbosity minimal
    if ($LASTEXITCODE -ne 0) {
        throw "Managed Release clean failed for '$Architecture'."
    }

    & dotnet build $shellProject --configuration Release --runtime $runtimeIdentifier --self-contained true `
        -p:Platform=$Architecture -p:Version=$Version -p:WindowsAppSDKSelfContained=false `
        -p:WindowsPackageType=MSIX -p:EnableMsixTooling=true `
        -p:AppxPackageSigningEnabled=false -p:GenerateAppxPackageOnBuild=true `
        -p:AppxBundle=Never -p:UapAppxPackageBuildMode=SideloadOnly `
        -p:AppxPackageDir=$packageDirectory\
    if ($LASTEXITCODE -ne 0) {
        throw "Packaged Release build failed for '$runtimeIdentifier'."
    }

    # Dependencies\ 아래에는 Windows App Runtime 프레임워크 패키지가 함께 놓인다. 앱
    # 패키지만 골라야 하므로 그 하위 폴더는 제외한다.
    $appPackages = @(Get-ChildItem -LiteralPath $packageDirectory -Recurse -Filter '*.msix' -File |
        Where-Object { $_.FullName -notmatch '\\Dependencies\\' })
    if ($appPackages.Count -ne 1) {
        throw "Expected exactly one application MSIX in '$packageDirectory' but found $($appPackages.Count)."
    }
    $appPackage = $appPackages[0].FullName

    # 그 프레임워크가 없는 기계에서는 앱 등록이 `0x80073CF3` 으로 거부된다 - 러너에서 실제로
    # 그렇게 거부됐다. 설치 프로그램은 사용자 권한으로 도는지라 나중에 깔아 줄 수도 없으므로,
    # 빌드가 여기 만들어 두는 Microsoft 서명 프레임워크 패키지를 설치본에 함께 싣는다.
    $runtimePackages = @(Get-ChildItem -LiteralPath $packageDirectory -Recurse -Filter '*.msix' -File |
        Where-Object {
            $parent = Split-Path -Parent $_.FullName
            (Split-Path -Leaf $parent) -eq $artifactArchitecture -and
            (Split-Path -Leaf (Split-Path -Parent $parent)) -eq 'Dependencies'
        })
    if ($runtimePackages.Count -ne 1) {
        throw ("Expected exactly one $artifactArchitecture Windows App Runtime MSIX under " +
            "'$packageDirectory\Dependencies' but found $($runtimePackages.Count).")
    }
    $runtimePackage = $runtimePackages[0].FullName

    $makeappxPath = Resolve-MakeAppx
    & $makeappxPath unpack /p $appPackage /d $payloadDirectory /o /nv
    if ($LASTEXITCODE -ne 0) {
        throw "Could not unpack the application MSIX: $appPackage"
    }

    # 블록 맵은 압축된 패키지의 무결성 목록이다. 느슨한 레이아웃을 등록할 때는 쓰이지
    # 않으므로 설치본에 싣지 않는다.
    $blockMap = Join-Path $payloadDirectory 'AppxBlockMap.xml'
    if (Test-Path -LiteralPath $blockMap) {
        Remove-Item -LiteralPath $blockMap -Force
    }

    # Package identity version has four fields and must follow the release version.
    $manifestPath = Join-Path $payloadDirectory 'AppxManifest.xml'
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $namespace = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
    $namespace.AddNamespace('appx', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $identity = $manifest.SelectSingleNode('/appx:Package/appx:Identity', $namespace)
    if ($null -eq $identity) {
        throw "Packaged manifest has no Identity: $manifestPath"
    }
    $identity.SetAttribute('Version', "$Version.0")
    $manifest.Save($manifestPath)

    Copy-Item -LiteralPath $packageRegistrationScript -Destination $payloadDirectory -Force

    # 카메라 RAW 디코더. Windows 는 RAW codec 을 기본 제공하지 않으므로 이것이 빠지면
    # DNG/CR2/NEF 가져오기가 Microsoft Store 확장이 깔린 기계에서만 됩니다. LGPL-2.1 이라
    # 라이선스 원문과 대응 소스를 같이 넣어야 합니다 — 셋 다 build-libraw.ps1 이 만듭니다.
    $librawDll = Join-Path $projectRoot "out\build\native\$nativePreset\Release\libraw.dll"
    if (-not (Test-Path -LiteralPath $librawDll)) {
        & (Join-Path $PSScriptRoot 'build-libraw.ps1') `
            -OutputDirectory (Split-Path -Parent $librawDll)
        if ($LASTEXITCODE -ne 0) { throw 'libraw.dll build failed.' }
    }
    if (-not (Test-Path -LiteralPath $librawDll)) {
        throw "Camera RAW decoder is missing: $librawDll"
    }
    Copy-Item -LiteralPath $librawDll -Destination $payloadDirectory -Force

    $librawLicenseDirectory = Join-Path $projectRoot 'build-libraw\redistributable'
    $librawNoticeDirectory = Join-Path $payloadDirectory 'licenses\libraw'
    New-Item -ItemType Directory -Force -Path $librawNoticeDirectory | Out-Null
    foreach ($librawNotice in @(
        'LICENSE.LGPL', 'LICENSE.CDDL', 'COPYRIGHT', 'LibRaw-0.22.2.tar.gz')) {
        $source = Join-Path $librawLicenseDirectory $librawNotice
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "LibRaw redistribution file is missing: $source. Run scripts\build-libraw.ps1."
        }
        Copy-Item -LiteralPath $source -Destination $librawNoticeDirectory -Force
    }

    foreach ($notice in @('LICENSE', 'NOTICE', 'negaflow-windows\\THIRD-PARTY-NOTICES.md')) {
        $source = Join-Path $repositoryRoot $notice
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Release notice is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $payloadDirectory -Force
    }

    foreach ($required in @(
        'Negaflow.Shell.exe',
        'Negaflow.Native.dll',
        'resources.pri',
        'AppxManifest.xml',
        'Assets\Negaflow.ico',
        'hostfxr.dll',
        'coreclr.dll',
        'package-registration.ps1',
        'LICENSE',
        'NOTICE',
        'THIRD-PARTY-NOTICES.md',
        'libraw.dll',
        'licenses\libraw\LICENSE.LGPL',
        'licenses\libraw\LICENSE.CDDL',
        'licenses\libraw\COPYRIGHT',
        'licenses\libraw\LibRaw-0.22.2.tar.gz'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $payloadDirectory $required))) {
            throw "Published payload is missing required file '$required'."
        }
    }

    Push-Location $OutputDirectory
    try {
        & $makensisPath '-V2' '-INPUTCHARSET' 'UTF8' "-DPAYLOAD=$payloadDirectory" `
            "-DRUNTIMEPACKAGE=$runtimePackage" `
            "-DVERSION=$Version" "-DARCH=$artifactArchitecture" $installerScript
        if ($LASTEXITCODE -ne 0) {
            throw 'NSIS compilation failed.'
        }
    }
    finally {
        Pop-Location
    }

    $compiledInstaller = Join-Path (Split-Path -Parent $installerScript) $installerName
    if (-not (Test-Path -LiteralPath $compiledInstaller)) {
        throw "NSIS did not create the installer: $compiledInstaller"
    }
    if (-not [string]::Equals($compiledInstaller, $installerPath, [StringComparison]::OrdinalIgnoreCase)) {
        Move-Item -LiteralPath $compiledInstaller -Destination $installerPath -Force
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$installerPath.sha256" -Encoding ASCII -NoNewline -Value "$hash *$installerName`n"
    Write-Host "Installer: $installerPath" -ForegroundColor Green
    Write-Host "SHA-256: $hash" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $payloadDirectory) {
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $packageDirectory) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    }
}
