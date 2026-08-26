<#
.SYNOPSIS
    투명 배경 원본 하나에서 Windows 앱 아이콘 자산을 만든다.

.DESCRIPTION
    **알파를 잃지 않는 것이 이 스크립트의 존재 이유다.** macOS 는 자기 앱 아이콘용으로
    일부러 불투명본(`AppIcon-App-1024.png`)을 만드는데(그것이 macOS 규칙이다), Windows
    자산이 그 불투명본에서 나오는 바람에 앱 아이콘·정보 창·부팅 로고가 전부 검은 사각형
    위에 얹혀 있었다. Windows 는 투명 원본(`AppIcon-1024.png`)에서 나와야 한다.

    만드는 것:
      Assets\AppIcon-1024.png   32bpp ARGB 원본 사본
      Assets\Negaflow.ico       16·20·24·32·40·48·64·256, 각 PNG 압축 32bpp
#>
[CmdletBinding()]
param(
    [string]$SourceIcon,
    [string]$AssetsDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$repositoryRoot = Split-Path -Parent $projectRoot
if ([string]::IsNullOrWhiteSpace($SourceIcon)) {
    $SourceIcon = Join-Path $repositoryRoot 'negaflow-mac\Sources\negaflowApp\Resources\AppIcon-1024.png'
}
if ([string]::IsNullOrWhiteSpace($AssetsDirectory)) {
    $AssetsDirectory = Join-Path $projectRoot 'src\Shell\Assets'
}
if (-not (Test-Path -LiteralPath $SourceIcon -PathType Leaf)) {
    throw "원본 아이콘이 없다: $SourceIcon"
}

$source = [System.Drawing.Image]::FromFile($SourceIcon)
try {
    if ($source.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) {
        throw "원본에 알파 채널이 없다($($source.PixelFormat)). 투명 원본을 줘야 한다: $SourceIcon"
    }
    $probe = New-Object System.Drawing.Bitmap($source)
    try {
        if ($probe.GetPixel(0, 0).A -ne 0) {
            throw '원본 모서리가 불투명하다. 불투명본을 원본으로 잘못 준 것이다.'
        }
    }
    finally { $probe.Dispose() }

    New-Item -ItemType Directory -Force -Path $AssetsDirectory | Out-Null
    $masterPath = Join-Path $AssetsDirectory 'AppIcon-1024.png'
    Copy-Item -LiteralPath $SourceIcon -Destination $masterPath -Force
    Write-Host "원본 사본: $masterPath"

    # Windows 셸이 실제로 고르는 크기들이다. 큰 것 하나만 넣으면 작업표시줄·탐색기가
    # 스스로 줄이면서 가장자리가 뭉갠다.
    $sizes = @(16, 20, 24, 32, 40, 48, 64, 256)
    $encoded = @()
    foreach ($size in $sizes) {
        $canvas = New-Object System.Drawing.Bitmap($size, $size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($source, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
        }
        finally { $graphics.Dispose() }
        $buffer = New-Object System.IO.MemoryStream
        $canvas.Save($buffer, [System.Drawing.Imaging.ImageFormat]::Png)
        $canvas.Dispose()
        $encoded += , @($size, $buffer.ToArray())
        $buffer.Dispose()
    }

    # ICO 컨테이너를 직접 쓴다. .NET 에는 다중 크기 ICO 를 내보내는 API 가 없다.
    $icoPath = Join-Path $AssetsDirectory 'Negaflow.ico'
    $stream = [System.IO.File]::Create($icoPath)
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0)                 # reserved
        $writer.Write([uint16]1)                 # type: icon
        $writer.Write([uint16]$encoded.Count)
        $offset = 6 + (16 * $encoded.Count)
        foreach ($entry in $encoded) {
            $size = $entry[0]; $bytes = $entry[1]
            $writer.Write([byte]$(if ($size -ge 256) { 0 } else { $size }))
            $writer.Write([byte]$(if ($size -ge 256) { 0 } else { $size }))
            $writer.Write([byte]0)               # 팔레트 없음
            $writer.Write([byte]0)               # reserved
            $writer.Write([uint16]1)             # color planes
            $writer.Write([uint16]32)            # bits per pixel
            $writer.Write([uint32]$bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $bytes.Length
        }
        foreach ($entry in $encoded) { $writer.Write($entry[1]) }
    }
    finally { $writer.Dispose(); $stream.Dispose() }
    Write-Host "아이콘: $icoPath ($($encoded.Count) 크기, 전부 32bpp 알파)"
}
finally { $source.Dispose() }
