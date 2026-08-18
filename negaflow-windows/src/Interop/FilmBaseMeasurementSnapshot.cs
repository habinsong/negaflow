namespace Negaflow.Interop;

/// <summary>
/// macOS <c>FilmBaseMeasurementDiagnostics</c> 의 내보낸 실측입니다. 사이드카 JSON 키는
/// Codable 속성 이름과 같습니다.
/// </summary>
public sealed class FilmBaseMeasurementSnapshot
{
    public const string ConfidenceBasis = "measuredEvidenceScoreV1";

    public static readonly string[] MethodNames =
    [
        "connectedComponent",
        "continuousBorder",
        "distributedMask",
        "stripFallback",
    ];

    public static readonly string[] AnomalyNames =
    [
        "fallbackEstimate",
        "lowSampleSupport",
        "sparseSampleCoverage",
        "limitedSpatialCoverage",
        "unstableLuma",
        "inconsistentChannels",
        "clippedSamples",
        "heavyOutlierRejection",
    ];

    public required int SchemaVersion { get; init; }

    public required string Method { get; init; }

    public required int SampledPixelCount { get; init; }

    public required int CandidateCount { get; init; }

    public required int SelectedSampleCount { get; init; }

    public required int RetainedSampleCount { get; init; }

    public required double SampleCoverage { get; init; }

    public required double SpatialCoverage { get; init; }

    public required double MedianLuma { get; init; }

    public required double LumaMad { get; init; }

    public required double[] ChannelMad { get; init; }

    public required double ChromaticityMad { get; init; }

    public required double ClippedFraction { get; init; }

    public required double OutlierFraction { get; init; }

    public required double SampleSupport { get; init; }

    public required double EvidenceSampleCoverage { get; init; }

    public required double EvidenceSpatialCoverage { get; init; }

    public required double LumaUniformity { get; init; }

    public required double ChannelConsistency { get; init; }

    public required double UnclippedSamples { get; init; }

    public required double InlierRetention { get; init; }

    public required double EvidenceScore { get; init; }

    public required bool IsCalibratedProbability { get; init; }

    public required IReadOnlyList<string> Anomalies { get; init; }

    public static string? MethodName(uint method) =>
        method < (uint)MethodNames.Length ? MethodNames[method] : null;

    public static IReadOnlyList<string> AnomaliesFromBits(uint bits)
    {
        var names = new List<string>(AnomalyNames.Length);
        for (int index = 0; index < AnomalyNames.Length; ++index)
        {
            if ((bits & (1u << index)) != 0)
            {
                names.Add(AnomalyNames[index]);
            }
        }
        return names;
    }
}
