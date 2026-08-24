[CmdletBinding()]
param(
    [string]$TracePath = (Join-Path $env:LOCALAPPDATA 'Negaflow\Logs\preview-trace.txt'),
    [ValidateRange(1, 10000)]
    [int]$MinimumSamples = 20
)

$ErrorActionPreference = 'Stop'
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$pattern = [regex]::new(
    'grainmend\.presentation id=(?<id>\d+) tool=(?<tool>[a-z]+) frame=(?<frame>\S+) ' +
    'target=(?<target>\S+) input_to_submit_ms=(?<submit>[0-9.]+) ' +
    'submit_to_composition_ms=(?<composition>[0-9.]+) ' +
    'input_to_composition_ms=(?<total>[0-9.]+) w=(?<width>\d+) h=(?<height>\d+)')

if (-not (Test-Path -LiteralPath $TracePath -PathType Leaf)) {
    throw "Trace file was not found: $TracePath"
}

$samples = foreach ($line in (Get-Content -LiteralPath $TracePath -Encoding UTF8)) {
    $match = $pattern.Match($line)
    if (-not $match.Success) {
        continue
    }
    [pscustomobject]@{
        Id = [long]::Parse($match.Groups['id'].Value, $invariant)
        Tool = $match.Groups['tool'].Value
        Frame = $match.Groups['frame'].Value
        Target = $match.Groups['target'].Value
        InputToSubmitMilliseconds = [double]::Parse(
            $match.Groups['submit'].Value, $invariant)
        SubmitToCompositionMilliseconds = [double]::Parse(
            $match.Groups['composition'].Value, $invariant)
        InputToCompositionMilliseconds = [double]::Parse(
            $match.Groups['total'].Value, $invariant)
        Width = [int]::Parse($match.Groups['width'].Value, $invariant)
        Height = [int]::Parse($match.Groups['height'].Value, $invariant)
    }
}

# 한 기능 입력으로 인정하는 완료 표면만 남깁니다. 예전 trace의 Brush drag 중간 frame과
# Clone cursor overlay는 tool 이름은 같지만 recipe 적용 결과가 아니므로 p95 표본이 아닙니다.
$eligibleSamples = @($samples | Where-Object {
    ($_.Tool -in @('auto', 'guided') -and $_.Target -eq 'defect-overlay') -or
    ($_.Tool -in @('infrared', 'brush', 'clone') -and $_.Target -eq 'develop-preview')
})

function Get-NearestRankPercentile {
    param([double[]]$Values, [double]$Percentile)
    if ($Values.Count -eq 0) {
        return $null
    }
    $ordered = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $ordered.Count) - 1
    return $ordered[[Math]::Max(0, $index)]
}

function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) {
        return $null
    }
    $ordered = @($Values | Sort-Object)
    $middle = [int]($ordered.Count / 2)
    if (($ordered.Count % 2) -eq 1) {
        return $ordered[$middle]
    }
    return ($ordered[$middle - 1] + $ordered[$middle]) / 2.0
}

$targets = @{
    auto = 5000.0
    guided = 1000.0
    infrared = 1000.0
}
$summaries = foreach ($tool in @('auto', 'guided', 'infrared', 'brush', 'clone')) {
    $rawToolSamples = @($samples | Where-Object Tool -eq $tool)
    $toolSamples = @($eligibleSamples | Where-Object Tool -eq $tool)
    $totals = [double[]]@($toolSamples | ForEach-Object InputToCompositionMilliseconds)
    $p95 = Get-NearestRankPercentile -Values $totals -Percentile 0.95
    $target = if ($targets.ContainsKey($tool)) { $targets[$tool] } else { $null }
    [pscustomobject]@{
        Tool = $tool
        Count = $toolSamples.Count
        RawCount = $rawToolSamples.Count
        IgnoredCount = $rawToolSamples.Count - $toolSamples.Count
        TargetMilliseconds = $target
        MinimumMilliseconds = if ($totals.Count) { ($totals | Measure-Object -Minimum).Minimum } else { $null }
        MedianMilliseconds = Get-Median -Values $totals
        P95Milliseconds = $p95
        MaximumMilliseconds = if ($totals.Count) { ($totals | Measure-Object -Maximum).Maximum } else { $null }
        AllReachedNextComposition = $toolSamples.Count -ge $MinimumSamples
        MeetsTarget = if ($null -ne $target) {
            $toolSamples.Count -ge $MinimumSamples -and $p95 -le $target
        } else {
            $null
        }
        Targets = @($toolSamples.Target | Sort-Object -Unique)
        Dimensions = @($toolSamples | ForEach-Object { "$($_.Width)x$($_.Height)" } | Sort-Object -Unique)
    }
}

[pscustomobject]@{
    Operation = 'grainmend-installed-winui-presentation'
    EvidenceBoundary = 'product input handler or IR selection scheduling through WriteableBitmap invalidation and the immediately following CompositionTarget.Rendering event; not physical scanout'
    TracePath = (Resolve-Path -LiteralPath $TracePath).Path
    MinimumSamples = $MinimumSamples
    Summaries = @($summaries)
} | ConvertTo-Json -Depth 6
