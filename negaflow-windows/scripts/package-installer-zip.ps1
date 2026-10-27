[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallerPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$InstallerPath = [System.IO.Path]::GetFullPath($InstallerPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and -not $Overwrite) {
    throw "ZIP already exists: $OutputPath. Pass -Overwrite to replace it."
}
$installerName = Split-Path -Leaf $InstallerPath
$installerHash = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('negaflow-setup-zip-' + [Guid]::NewGuid().ToString('N'))
$temporaryZip = Join-Path (Split-Path -Parent $OutputPath) ('.setup-' + [Guid]::NewGuid().ToString('N') + '.zip')
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    Copy-Item -LiteralPath $InstallerPath -Destination $staging
    foreach ($notice in @('LICENSE', 'NOTICE', 'TRADEMARKS.md', 'negaflow-windows\THIRD-PARTY-NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $notice) -Destination $staging
    }
    $readme = @"
negaflow $Version - Windows x64

English: Extract all files, then run $installerName. This ZIP contains the installer; it is not a portable app. SmartScreen may still warn. Verify the download source and the SHA-256 checksum before running.

한국어: 압축을 모두 푼 뒤 $installerName 파일을 실행하세요. 이 ZIP은 설치 파일 압축본이며 포터블 앱이 아닙니다. SmartScreen 경고는 여전히 나올 수 있습니다. 실행 전에 다운로드 출처와 SHA-256 체크섬을 확인하세요.

日本語: すべて展開してから $installerName を実行してください。このZIPはインストーラーの圧縮版で、ポータブル版ではありません。SmartScreenの警告が出る場合があります。実行前に配布元とSHA-256を確認してください。

简体中文：解压全部文件后运行 $installerName。此ZIP包含安装程序，并非便携版。仍可能出现SmartScreen提示。运行前请确认下载来源和SHA-256校验和。

Français : Extrayez tous les fichiers, puis lancez $installerName. Ce ZIP contient le programme d'installation, pas une version portable. SmartScreen peut encore afficher un avertissement. Vérifiez la provenance et la somme SHA-256 avant l'exécution.

Deutsch: Entpacken Sie alle Dateien und starten Sie $installerName. Dieses ZIP enthält das Installationsprogramm, keine portable App. SmartScreen kann weiterhin warnen. Prüfen Sie vor dem Start die Quelle und die SHA-256-Prüfsumme.

Release / sources: https://github.com/habinsong/negaflow/releases/tag/v$Version
"@
    Set-Content -LiteralPath (Join-Path $staging 'README.txt') -Encoding UTF8 -Value $readme
    $checksums = Get-ChildItem -LiteralPath $staging -File | Sort-Object Name | ForEach-Object {
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + ' *' + $_.Name
    }
    Set-Content -LiteralPath (Join-Path $staging 'SHA256SUMS.txt') -Encoding ASCII -Value $checksums
    Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $staging -File).FullName -DestinationPath $temporaryZip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($temporaryZip)
    try {
        $entry = $archive.GetEntry($installerName)
        if ($null -eq $entry) { throw 'Installer is missing from the ZIP.' }
        $stream = $entry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $packedHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose(); $stream.Dispose() }
        if ($packedHash -ne $installerHash) { throw 'ZIP installer does not match the standalone EXE.' }
    }
    finally { $archive.Dispose() }
    Move-Item -LiteralPath $temporaryZip -Destination $OutputPath -Force
    Write-Host "Installer ZIP: $OutputPath"
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue
}
