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

$installerName = "negaflow-$Version-win-$artifactArchitecture.exe"
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

$nsisVersionText = ((& $makensisPath '-VERSION') -join "`n").Trim()
if ($LASTEXITCODE -ne 0 -or $nsisVersionText -notmatch '^v(?<Release>3\.\d+(?:\.\d+)?)$') {
    throw "Expected a stable NSIS 3 release, got '$nsisVersionText'."
}
$nsisVersion = $Matches.Release
$nsisSourceName = "nsis-$nsisVersion-src.tar.bz2"
$nsisSourceUrl = "https://downloads.sourceforge.net/project/nsis/NSIS%203/$nsisVersion/$nsisSourceName"
$nsisReleaseSourceUrl = "https://github.com/habinsong/negaflow/releases/download/v$Version/$nsisSourceName"

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

    # 음화 RAW는 LibRaw 카메라 RGB를 사용합니다. 업스트림의 CDDL-1.0을 선택하며
    # 디코더와 라이선스 원문·대응 소스를 함께 패키징합니다.
    $librawDll = Join-Path $projectRoot "out\build\native\$nativePreset\Release\libraw.dll"
    if (-not (Test-Path -LiteralPath $librawDll)) {
        & (Join-Path $PSScriptRoot 'build-libraw.ps1') `
            -Architecture $Architecture `
            -OutputDirectory (Split-Path -Parent $librawDll)
        if ($LASTEXITCODE -ne 0) { throw 'libraw.dll build failed.' }
    }
    if (-not (Test-Path -LiteralPath $librawDll)) {
        throw "Camera RAW decoder is missing: $librawDll"
    }
    Copy-Item -LiteralPath $librawDll -Destination $payloadDirectory -Force

    # LibRaw 는 OpenMP 로 디모자이크를 코어에 나눕니다. 그 런타임은 정적으로 링크할 수 없어
    # 곁에 둡니다 - 없으면 libraw.dll 이 아예 로드되지 않습니다. `build-libraw.ps1` 이 Visual
    # Studio 의 재배포 자리에서 골라 놓아 둔 것을 그대로 집습니다.
    $openMpRuntime = Join-Path (Split-Path -Parent $librawDll) 'vcomp140.dll'
    if (-not (Test-Path -LiteralPath $openMpRuntime -PathType Leaf)) {
        throw "OpenMP runtime is missing: $openMpRuntime. Run scripts\build-libraw.ps1."
    }
    Copy-Item -LiteralPath $openMpRuntime -Destination $payloadDirectory -Force

    $librawLicenseDirectory = Join-Path $projectRoot 'build-libraw\redistributable'
    $librawNoticeDirectory = Join-Path $payloadDirectory 'licenses\libraw'
    New-Item -ItemType Directory -Force -Path $librawNoticeDirectory | Out-Null
    foreach ($librawNotice in @('LICENSE.LGPL', 'LICENSE.CDDL', 'COPYRIGHT', 'Changelog.txt')) {
        $source = Join-Path $librawLicenseDirectory $librawNotice
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "LibRaw redistribution file is missing: $source. Run scripts\build-libraw.ps1."
        }
        Copy-Item -LiteralPath $source -Destination $librawNoticeDirectory -Force
    }
    $additionalNotice = Join-Path $repositoryRoot 'negaflow-mac\Config\LibRaw-Third-Party-Notices.txt'
    if (Test-Path -LiteralPath $additionalNotice -PathType Leaf) {
        Copy-Item -LiteralPath $additionalNotice -Destination $librawNoticeDirectory -Force
    } else {
        Write-Warning 'Supplemental LibRaw notice is missing; upstream source and licence files are retained.'
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-libraw.ps1') `
        -Destination (Join-Path $librawNoticeDirectory 'build-libraw.ps1') -Force
    # CDDL 배포 소스. 파일 이름을 여기 적어 두면 LibRaw 를 올릴 때마다 이 줄이 어긋나고,
    # 어긋난 것은 빌드가 아니라 배포 뒤에 드러납니다. `build-libraw.ps1` 이 놓아 둔 것을
    # 그대로 집되, 없거나 둘 이상이면 세웁니다.
    $librawSource = @(Get-ChildItem -LiteralPath $librawLicenseDirectory -Filter 'LibRaw-*.tar.gz' -File)
    if ($librawSource.Count -ne 1) {
        throw ("Expected exactly one LibRaw corresponding-source archive in " +
            "'$librawLicenseDirectory' but found $($librawSource.Count). Run scripts\build-libraw.ps1.")
    }
    Copy-Item -LiteralPath $librawSource[0].FullName -Destination $librawNoticeDirectory -Force
    $librawSourceName = $librawSource[0].Name

    # 복원된 NuGet 패키지 디렉터리에서 실제 배포 버전의 라이선스·NOTICE 원문을 수집한다.
    $nugetGlobalPackages = if (-not [string]::IsNullOrWhiteSpace($env:NUGET_PACKAGES)) {
        $env:NUGET_PACKAGES
    }
    else {
        Join-Path $HOME '.nuget\packages'
    }
    $nugetLicenseDirectory = Join-Path $payloadDirectory 'licenses\nuget'
    New-Item -ItemType Directory -Force -Path $nugetLicenseDirectory | Out-Null
    $pinnedNuGetPackages = @(
        @{ Id = 'microsoft.windowsappsdk.runtime'; Version = '1.8.260710003' },
        @{ Id = 'microsoft.windowsappsdk.winui'; Version = '1.8.260709004' },
        @{ Id = 'microsoft.windowsappsdk.base'; Version = '1.8.251216001' },
        @{ Id = 'microsoft.windowsappsdk.foundation'; Version = '1.8.260709000' },
        @{ Id = 'microsoft.windowsappsdk.interactiveexperiences'; Version = '1.8.260708001' },
        @{ Id = 'microsoft.windowsappsdk.ai'; Version = '1.8.79' },
        @{ Id = 'microsoft.windowsappsdk.dwrite'; Version = '1.8.25122902' },
        @{ Id = 'microsoft.windowsappsdk.ml'; Version = '1.8.2197' },
        @{ Id = 'microsoft.windowsappsdk.widgets'; Version = '1.8.251231004' },
        @{ Id = 'microsoft.data.sqlite.core'; Version = '10.0.10' },
        @{ Id = 'sqlitepclraw.config.e_sqlite3'; Version = '3.0.5' },
        @{ Id = 'sqlitepclraw.provider.e_sqlite3'; Version = '3.0.5' },
        @{ Id = 'sqlitepclraw.core'; Version = '3.0.5' },
        @{ Id = 'sourcegear.sqlite3'; Version = '3.53.4' },
        @{ Id = 'system.numerics.tensors'; Version = '9.0.0' }
    )
    $dotnetRuntimePacks = @(Get-ChildItem -LiteralPath $nugetGlobalPackages -Directory -Filter "microsoft.netcore.app.runtime.$runtimeIdentifier" -ErrorAction SilentlyContinue)
    foreach ($packDir in $dotnetRuntimePacks) {
        $latestVer = Get-ChildItem -LiteralPath $packDir.FullName -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($null -ne $latestVer) {
            $pinnedNuGetPackages += @{ Id = $packDir.Name; Version = $latestVer.Name }
        }
    }
    foreach ($pkg in $pinnedNuGetPackages) {
        $pkgRoot = Join-Path $nugetGlobalPackages "$($pkg.Id)\$($pkg.Version)"
        if (Test-Path -LiteralPath $pkgRoot -PathType Container) {
            $destDir = Join-Path $nugetLicenseDirectory "$($pkg.Id).$($pkg.Version)"
            $licenseFiles = @(Get-ChildItem -LiteralPath $pkgRoot -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(license|notice|third[-_]?party[-_]?notices)(\.txt|\.md)?$' })
            if ($licenseFiles.Count -gt 0) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                foreach ($file in $licenseFiles) {
                    Copy-Item -LiteralPath $file.FullName -Destination $destDir -Force
                }
            }
        }
    }

    $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $dotnetCommand) {
        $dotnetRoot = Split-Path -Parent $dotnetCommand.Source
        $dotnetLicenseDest = Join-Path $payloadDirectory 'licenses\dotnet'
        foreach ($dotnetNotice in @('LICENSE.txt', 'THIRD-PARTY-NOTICES.TXT')) {
            $candidate = Join-Path $dotnetRoot $dotnetNotice
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                New-Item -ItemType Directory -Force -Path $dotnetLicenseDest | Out-Null
                Copy-Item -LiteralPath $candidate -Destination $dotnetLicenseDest -Force
            }
        }
    }

    # 설치기에 사용한 NSIS 버전의 원본 소스를 별도 릴리스 자산으로 준비한다.
    $nsisSourceArchive = Join-Path $packageDirectory $nsisSourceName
    Invoke-WebRequest -Uri $nsisSourceUrl -OutFile $nsisSourceArchive -UseBasicParsing -UserAgent 'Negaflow-license-packaging/1.0'
    $nsisSourceEntries = @(& tar.exe -tjf $nsisSourceArchive "nsis-$nsisVersion-src/COPYING")
    if ($LASTEXITCODE -ne 0 -or $nsisSourceEntries.Count -ne 1) {
        throw "NSIS source archive is invalid: $nsisSourceUrl"
    }
    $nsisSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $nsisSourceArchive).Hash.ToLowerInvariant()
    $nsisNoticeDirectory = Join-Path $payloadDirectory 'licenses\nsis'
    New-Item -ItemType Directory -Force -Path $nsisNoticeDirectory | Out-Null
    $nsisSourceNotice = @"
NSIS $nsisVersion

The installer includes the NSIS installer stub and its LZMA compression module.
The license terms, including CPL-1.0 and the LZMA linking exception, are in COPYING.

Source archive: $nsisSourceName
SHA-256: $nsisSourceHash
Negaflow release source download: $nsisReleaseSourceUrl
Upstream source download: $nsisSourceUrl
"@
    Set-Content -LiteralPath (Join-Path $nsisNoticeDirectory 'SOURCE.txt') -Encoding UTF8 -Value $nsisSourceNotice

    foreach ($notice in @('LICENSE', 'NOTICE', 'TRADEMARKS.md', 'negaflow-windows\\THIRD-PARTY-NOTICES.md')) {
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
        'TRADEMARKS.md',
        'THIRD-PARTY-NOTICES.md',
        'licenses\nsis\SOURCE.txt',
        'libraw.dll',
        'vcomp140.dll',
        'licenses\libraw\LICENSE.LGPL',
        'licenses\libraw\LICENSE.CDDL',
        'licenses\libraw\COPYRIGHT',
        'licenses\libraw\Changelog.txt',
        'licenses\libraw\build-libraw.ps1',
        "licenses\libraw\$librawSourceName"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $payloadDirectory $required))) {
            throw "Published payload is missing required file '$required'."
        }
    }

    # 설치 화면이 쓰는 브랜딩 비트맵. 앱 아이콘에서 매번 구워 아이콘을 바꾸면 설치 화면도
    # 같이 바뀌게 한다 - 저장소에 BMP 를 넣어 두면 둘이 어긋난다.
    $brandingDirectory = Join-Path $OutputDirectory ('.branding-' + [Guid]::NewGuid().ToString('N'))
    & py -3 (Join-Path $PSScriptRoot 'generate-installer-branding.py') `
        --source (Join-Path $projectRoot 'src\Shell\Assets\AppIcon-1024.png') `
        --output $brandingDirectory
    foreach ($bitmap in @('welcome.bmp', 'header.bmp')) {
        if (-not (Test-Path -LiteralPath (Join-Path $brandingDirectory $bitmap) -PathType Leaf)) {
            throw "Installer branding bitmap was not produced: $bitmap"
        }
    }

    Push-Location $OutputDirectory
    try {
        & $makensisPath '-V2' '-INPUTCHARSET' 'UTF8' "-DPAYLOAD=$payloadDirectory" `
            "-DRUNTIMEPACKAGE=$runtimePackage" `
            "-DBRANDING=$brandingDirectory" `
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
    $nsisPublishedSource = Join-Path $OutputDirectory $nsisSourceName
    Move-Item -LiteralPath $nsisSourceArchive -Destination $nsisPublishedSource -Force
    Set-Content -LiteralPath "$nsisPublishedSource.sha256" -Encoding ASCII -NoNewline `
        -Value "$nsisSourceHash *$nsisSourceName`n"
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($installerPath, '.sha256')) -Encoding ASCII -NoNewline -Value "$hash *$installerName`n"
    Write-Host "Installer: $installerPath" -ForegroundColor Green
    Write-Host "SHA-256: $hash" -ForegroundColor Green
    Write-Host "NSIS source: $nsisPublishedSource" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $payloadDirectory) {
        Remove-Item -LiteralPath $payloadDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $packageDirectory) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force
    }
    if ($null -ne $brandingDirectory -and (Test-Path -LiteralPath $brandingDirectory)) {
        Remove-Item -LiteralPath $brandingDirectory -Recurse -Force
    }
}
