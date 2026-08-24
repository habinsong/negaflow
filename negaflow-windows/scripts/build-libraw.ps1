<#
.SYNOPSIS
    함께 배포하는 카메라 RAW 디코더 `libraw.dll` 을 고정된 upstream 소스에서 빌드한다.

.DESCRIPTION
    Windows 는 카메라 RAW codec 을 기본 제공하지 않는다. Microsoft 공식 WIC 문서가 기본
    제공이라고 적은 codec 은 BMP·GIF·ICO·JPEG·JPEG XR·PNG·TIFF·HD Photo·DDS 아홉 개뿐이고
    RAW 은 Microsoft Store 의 별도 무료 패키지 `Raw Image Extension` 이다. macOS 는 ImageIO
    에 RAW 이 들어 있으므로, 이 DLL 이 없으면 같은 파일이 맥에서는 열리고 Windows 에서만
    안 열린다.

    저장소에 바이너리를 넣지 않는다. `negaflow-scanner-sane` 의 SANE 런타임과 같은 규율로
    **고정된 URL + SHA-256 + 빌드 레시피**만 두고 이 스크립트가 만든다.

.PARAMETER OutputDirectory
    빌드한 `libraw.dll` 을 놓을 곳. 기본값은 x64-release native 출력 폴더다.

.PARAMETER WorkRoot
    소스를 풀고 빌드할 작업 디렉터리. 기본값은 저장소의 build-libraw\ (gitignore 대상).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-libraw.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$WorkRoot,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── 고정된 upstream ──────────────────────────────────────────────────────────
# 버전을 올릴 때는 URL 과 해시를 같이 고치고, THIRD-PARTY-NOTICES.md 와
# third_party\manifest\components.json 의 같은 값도 함께 고친다.
$LibRawVersion = '0.22.2'
$LibRawUrl = "https://www.libraw.org/data/LibRaw-$LibRawVersion.tar.gz"
$LibRawSha256 = 'de86b035655accff8d4010f1a221fdf50d353cb7b1422ba26f14a0db92612cfa'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
if (-not $WorkRoot) { $WorkRoot = Join-Path $repoRoot 'build-libraw' }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'out\build\native\x64-release\Release'
}

if ($Clean -and (Test-Path $WorkRoot)) { Remove-Item -Recurse -Force $WorkRoot }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

# ── 1. 소스를 받고 해시를 확인한다 ───────────────────────────────────────────
$archive = Join-Path $WorkRoot "LibRaw-$LibRawVersion.tar.gz"
if (-not (Test-Path $archive)) {
    Write-Host "LibRaw $LibRawVersion 소스를 받는다"
    Invoke-WebRequest -Uri $LibRawUrl -OutFile $archive -UseBasicParsing
}
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $LibRawSha256) {
    throw "LibRaw 소스 해시가 다르다. 기대 $LibRawSha256, 실제 $actual"
}
Write-Host "SHA-256 확인: $actual"

# ── 2. 푼다 ──────────────────────────────────────────────────────────────────
$sourceDir = Join-Path $WorkRoot "LibRaw-$LibRawVersion"
if (-not (Test-Path $sourceDir)) {
    & tar.exe -xzf $archive -C $WorkRoot
    if ($LASTEXITCODE -ne 0) { throw "LibRaw 소스를 풀지 못했다 (exit $LASTEXITCODE)." }
}

# ── 3. MSVC 로 빌드한다 ──────────────────────────────────────────────────────
# LibRaw 의 CMake 스크립트는 upstream 이 공식 지원하지 않는다(README.cmake). 저장소가
# 함께 주는 Makefile.msvc 를 그대로 쓴다. 추가 의존성(RawSpeed·DNG SDK·LCMS·JPEG)은
# 전부 끈 기본값이라 libraw.dll 은 다른 DLL 을 요구하지 않는다.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere 를 찾지 못했다: $vswhere" }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw "MSVC x64 도구를 가진 Visual Studio 설치를 찾지 못했다." }
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat 을 찾지 못했다: $vcvars" }

foreach ($sub in @('bin', 'lib', 'object')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $sourceDir $sub) | Out-Null
}
Write-Host "MSVC x64 로 libraw.dll 을 빌드한다"
& cmd /c "`"$vcvars`" >nul 2>&1 && cd /d `"$sourceDir`" && nmake -f Makefile.msvc bin\libraw.dll"
if ($LASTEXITCODE -ne 0) { throw "libraw.dll 빌드가 실패했다 (exit $LASTEXITCODE)." }

$built = Join-Path $sourceDir 'bin\libraw.dll'
if (-not (Test-Path $built)) { throw "빌드 산출물이 없다: $built" }

# ── 4. C API 심볼이 전부 있는지 확인한다 ─────────────────────────────────────
# 없는 심볼이 하나라도 있으면 native 쪽 `libraw_decoder_available()` 이 통째로 거부하므로,
# 배포 전에 여기서 잡는다.
$required = @(
    'libraw_init', 'libraw_open_wfile', 'libraw_unpack', 'libraw_dcraw_process',
    'libraw_dcraw_make_mem_image', 'libraw_dcraw_clear_mem', 'libraw_close',
    'libraw_set_output_bps', 'libraw_set_output_color', 'libraw_set_gamma',
    'libraw_set_no_auto_bright', 'libraw_set_highlight', 'libraw_set_user_mul',
    'libraw_get_cam_mul', 'libraw_version')
# dumpbin 은 여러 줄을 돌려주므로 **한 문자열로 합쳐서** 본다. 배열에 `-notmatch` 를 쓰면
# boolean 이 아니라 "안 맞는 원소들" 이 나와서 거의 항상 참이 된다 — 실제로 이 스크립트가
# 처음에 모든 심볼을 없다고 보고한 원인이 그것이었다.
$exports = (& cmd /c "`"$vcvars`" >nul 2>&1 && dumpbin /exports `"$built`"") -join "`n"
$missing = @($required | Where-Object { $exports -notmatch "\b$([regex]::Escape($_))\b" })
if ($missing) { throw "libraw.dll 에 필요한 C API 가 없다: $($missing -join ', ')" }
Write-Host "C API 심볼 $($required.Count) 개 확인"

# ── 5. 출력 폴더와 GPL/LGPL 고지 자료를 놓는다 ───────────────────────────────
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Copy-Item -LiteralPath $built -Destination $OutputDirectory -Force

# LGPL-2.1 은 라이선스 사본과 대응 소스를 함께 주어야 한다. 배포 payload 를 만드는 쪽이
# 집어갈 수 있도록 한곳에 모아 둔다.
$licenseDir = Join-Path $WorkRoot 'redistributable'
New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
foreach ($name in @('LICENSE.LGPL', 'LICENSE.CDDL', 'COPYRIGHT', 'Changelog.txt')) {
    $file = Join-Path $sourceDir $name
    if (Test-Path $file) { Copy-Item -LiteralPath $file -Destination $licenseDir -Force }
}
Copy-Item -LiteralPath $archive -Destination $licenseDir -Force

$hash = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'libraw.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "libraw.dll → $OutputDirectory"
Write-Host "SHA-256: $hash"
Write-Host "LGPL 배포 자료(라이선스 + 대응 소스): $licenseDir"
