namespace Negaflow.Interop;

public enum DevelopExportFormat
{
    Png16 = 0,
    Tiff16 = 1,
    Jpeg8 = 2,
}

public enum DevelopTiffCompression
{
    None = 0,
    Lzw = 1,
    Deflate = 2,
}

public enum NegativeFilmType
{
    Color = 0,
    BlackAndWhite = 1,
}

public enum FilmPolarity
{
    Negative = 0,
    Positive = 1,
}

public enum DevelopBaseEstimationMode
{
    Auto = 0,
    Preset = 1,
    Manual = 2,
}

public enum DevelopBaseSource
{
    Manual = 0,
    AutoSceneEdge = 1,
    AutoFallback = 2,
    AutoConnectedComponent = 3,
    AutoContinuousBorder = 4,
    AutoDistributedMask = 5,
    AutoStripFallback = 6,
    PresetMeasured = 7,
    PresetFallback = 8,
}

public enum DevelopSourceKind
{
    FilmScan = 0,
    RenderedDigital = 1,
}

public enum DevelopTargetMode
{
    Main = 0,
    Print = 1,
    Noritsu = 2,
    Sp3000 = 3,
    F135 = 4,
    Hr = 5,
    Rescue = 6,
}

/// <summary>The four macOS FilmScanDenoise film-response profiles.</summary>
public enum FilmScanDenoiseFilmProfile
{
    ColorNegative = 0,
    ColorPositive = 1,
    BlackAndWhiteNegative = 2,
    BlackAndWhitePositive = 3,
}

public enum BwToningMode
{
    None = 0,
    Selenium = 1,
    Sepia = 2,
}

public enum DevelopImageRotation
{
    Degrees0 = 0,
    Degrees90 = 1,
    Degrees180 = 2,
    Degrees270 = 3,
}

/// <summary>
/// The space a published file is encoded in. macOS offers the same three.
/// </summary>
/// <summary>
/// What a published file carries. macOS offers the same four.
/// </summary>
public enum ExportMetadataPolicy
{
    /// <summary>Nothing from the source; only what the app knows. macOS default.</summary>
    Minimal = 0,
    /// <summary>Rights only. Not even the scanner or the software name.</summary>
    CopyrightOnly = 1,
    RemoveLocation = 2,
    All = 3,
}

/// <summary>
/// Values written into the published file. An empty string leaves its tag out.
/// </summary>
public sealed record ExportMetadataValues
{
    public string Make { get; init; } = string.Empty;

    public string Model { get; init; } = string.Empty;

    public string Software { get; init; } = string.Empty;

    public string Artist { get; init; } = string.Empty;

    public string Copyright { get; init; } = string.Empty;

    public string FilmType { get; init; } = string.Empty;

    public string FilmStock { get; init; } = string.Empty;

    /// <summary>EXIF form, <c>yyyy:MM:dd HH:mm:ss</c>, UTC.</summary>
    public string CapturedAt { get; init; } = string.Empty;
}

public enum ExportColorSpace
{
    Srgb = 0,
    DisplayP3 = 1,
    AdobeRgb = 2,
}

public enum OutputSharpeningMedium
{
    Screen = 0,
    MattePaper = 1,
    GlossyPaper = 2,
}
