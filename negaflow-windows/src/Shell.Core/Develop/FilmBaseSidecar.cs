using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>Sidecar.BaseSample</c> / <c>Sidecar.FilmBaseDiagnostics.init</c> 입니다.
/// </summary>
public sealed record FilmBaseSampleSidecar
{
    public required double R { get; init; }

    public required double G { get; init; }

    public required double B { get; init; }

    public required string Source { get; init; }
}

public sealed record FilmBaseDiagnosticsSidecar
{
    public required double[] Rgb { get; init; }

    public required string Source { get; init; }

    public required double[] Dmin { get; init; }

    public double[]? Dmax { get; init; }

    public double[]? DensityRange { get; init; }

    public double? Confidence { get; init; }

    public string? ConfidenceBasis { get; init; }

    public bool? ConfidenceIsCalibratedProbability { get; init; }

    public FilmBaseMeasurementSnapshot? Measurement { get; init; }

    /// <summary>macOS <c>Sidecar.FilmBaseDiagnostics.init(_ fb: FilmBase)</c>.</summary>
    public static FilmBaseDiagnosticsSidecar From(
        double red,
        double green,
        double blue,
        string source,
        FilmBaseMeasurementSnapshot? measurement)
    {
        double[] rgb = [red, green, blue];
        return new FilmBaseDiagnosticsSidecar
        {
            Rgb = rgb,
            Source = source,
            Dmin =
            [
                Density(red),
                Density(green),
                Density(blue),
            ],
            Dmax = null,
            DensityRange = null,
            Measurement = measurement,
            Confidence = measurement?.EvidenceScore,
            ConfidenceBasis = measurement is null
                ? null
                : FilmBaseMeasurementSnapshot.ConfidenceBasis,
            ConfidenceIsCalibratedProbability = measurement?.IsCalibratedProbability,
        };
    }

    /// <summary>
    /// macOS <c>FilmBase.Source</c> raw 값입니다. 연결 성분·분산 마스크는
    /// <c>auto</c>, 연속 보더·스트립 폴백은 <c>border</c>, 수동·프리셋 폴백은
    /// <c>manual</c> 입니다.
    /// </summary>
    public static string SourceName(DevelopBaseSource baseSource, string? method)
    {
        if (method == "connectedComponent" || method == "distributedMask")
        {
            return "auto";
        }
        if (method == "continuousBorder" || method == "stripFallback")
        {
            return "border";
        }
        return baseSource is DevelopBaseSource.Manual or DevelopBaseSource.PresetFallback
            ? "manual"
            : "auto";
    }

    public static FilmBaseSampleSidecar Sample(
        double red,
        double green,
        double blue,
        string source) =>
        new() { R = red, G = green, B = blue, Source = source };

    private static double Density(double transmission) =>
        -Math.Log10(Math.Max(transmission, 1.0e-6));
}
