[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Register', 'Unregister')]
    [string]$Action,

    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$packageName = 'Negaflow.Windows'

if ($Action -eq 'Unregister') {
    Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue |
        Remove-AppxPackage -ErrorAction Stop
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    throw 'ManifestPath is required for package registration.'
}
$ManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Package manifest does not exist: $ManifestPath"
}

Add-AppxPackage -Register $ManifestPath -ForceApplicationShutdown -ForceUpdateFromAnyVersion
