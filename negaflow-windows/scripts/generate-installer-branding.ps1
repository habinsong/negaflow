<#
.SYNOPSIS
    설치 프로그램이 쓰는 브랜딩 비트맵을 앱 아이콘에서 만든다.

.DESCRIPTION
    NSIS 는 BMP 만 받고 알파를 읽지 않는다. 그래서 투명 아이콘을 각 화면의 실제 배경색 위에
    합성해서 굽는다 - 그러지 않으면 아이콘 뒤에 검은 사각형이 남는다.

    만드는 것:
      welcome.bmp  164x314  환영·완료 화면 왼쪽 판. 짙은 바탕에 아이콘과 워드마크.
      header.bmp   150x57   나머지 화면 머리글. 밝은 바탕에 아이콘만.

    90 년대 설치 마법사처럼 보이지 않게 하는 것이 요점이다 - 그라데이션·입체 테두리·비스듬한
    그림자를 쓰지 않고, 평평한 면과 넉넉한 여백만 쓴다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$SourceIcon,
    [Parameter(Mandatory)] [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $SourceIcon -PathType Leaf)) {
    throw "아이콘 원본이 없다: $SourceIcon"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$icon = [System.Drawing.Image]::FromFile($SourceIcon)
try {
    function New-Graphics {
        param([System.Drawing.Bitmap]$Bitmap, [System.Drawing.Color]$Background)
        $g = [System.Drawing.Graphics]::FromImage($Bitmap)
        $g.Clear($Background)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        return $g
    }

    # -- 환영/완료 화면 왼쪽 판 (164x314) --------------------------------------
    $welcome = New-Object System.Drawing.Bitmap(164, 314,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-Graphics $welcome ([System.Drawing.Color]::FromArgb(24, 24, 27))
    $iconSize = 88
    $iconLeft = [int](($welcome.Width - $iconSize) / 2)
    $g.DrawImage($icon, (New-Object System.Drawing.Rectangle($iconLeft, 78, $iconSize, $iconSize)))
    $word = New-Object System.Drawing.Font('Bahnschrift', 13, [System.Drawing.FontStyle]::Bold)
    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString('NEGAFLOW', $word, [System.Drawing.Brushes]::White,
        (New-Object System.Drawing.RectangleF(0, 182, $welcome.Width, 24)), $center)
    # 워드마크 아래 가느다란 강조선 하나. 장식은 이것뿐이다.
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(239, 139, 38))
    $accentLeft = [int](($welcome.Width - 28) / 2)
    $g.FillRectangle($accent, $accentLeft, 212, 28, 2)
    $accent.Dispose(); $word.Dispose(); $center.Dispose(); $g.Dispose()
    $welcome.Save((Join-Path $OutputDirectory 'welcome.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $welcome.Dispose()

    # -- 머리글 (150x57) -------------------------------------------------------
    # 마법사 머리글은 시스템이 흰색으로 칠한다. 같은 흰색 위에 아이콘만 얹는다.
    $header = New-Object System.Drawing.Bitmap(150, 57,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-Graphics $header ([System.Drawing.Color]::White)
    $headerIcon = 40
    $headerLeft = $header.Width - $headerIcon - 12
    $headerTop = [int](($header.Height - $headerIcon) / 2)
    $g.DrawImage($icon, (New-Object System.Drawing.Rectangle($headerLeft, $headerTop, $headerIcon, $headerIcon)))
    $g.Dispose()
    $header.Save((Join-Path $OutputDirectory 'header.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp)
    $header.Dispose()

    Write-Host "브랜딩 비트맵: $OutputDirectory (welcome.bmp, header.bmp)"
}
finally { $icon.Dispose() }
