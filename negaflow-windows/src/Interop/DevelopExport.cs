namespace Negaflow.Interop;

public enum DevelopExportFormat
{
    Png16 = 0,
    Tiff16 = 1,
}

public enum NegativeFilmType
{
    Color = 0,
    BlackAndWhite = 1,
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

/// <summary>
/// Values match the native <c>FilmEmulation</c> enum and the names persisted by
/// <c>Negaflow.Catalog.Core</c>. The native side maps each value explicitly rather
/// than casting, so adding a profile cannot silently reinterpret a stored recipe.
/// </summary>
public enum FilmEmulationProfile
{
    None = 0,
    EktachromeE100 = 1,
    Provia100F = 2,
    Velvia50 = 3,
    Portra160 = 4,
    Portra400 = 5,
    Portra800 = 6,
    Ektar100 = 7,
    Ultramax400 = 8,
    ColorPlus200 = 9,
    FujicolorC200 = 10,
    Pro400H = 11,
}

/// <summary>Which stage refused. Mirrors <c>NF_DEVELOP_STAGE_*</c>.</summary>
public enum DevelopExportStage
{
    None = 0,
    RequestValidation = 1,
    ObserveSourceBefore = 2,
    Decode = 3,
    ObserveSourceAfter = 4,
    FilmLookWorkspace = 5,
    Develop = 6,
    ToneAdjust = 7,
    FilmLook = 8,
    Output = 9,
}

public enum FilmLookRoute
{
    Invalid = 0,
    Identity = 1,
    FilmScanEmulation = 2,
    DigitalFilmLook = 3,
}

/// <summary>한 Point Curve 채널의 정규화된 입출력 좌표입니다.</summary>
public readonly record struct DevelopPointCurvePoint(double X, double Y);

/// <summary>
/// macOS와 같은 RGB/Red/Green/Blue Point Curve recipe입니다. 빈 채널은 identity를 뜻합니다.
/// </summary>
public sealed class DevelopPointCurves
{
    public IReadOnlyList<DevelopPointCurvePoint> Rgb { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Red { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Green { get; init; } = [];

    public IReadOnlyList<DevelopPointCurvePoint> Blue { get; init; } = [];
}

/// <summary>macOS와 같은 HSL 8밴드 Color Mixer recipe입니다.</summary>
public sealed class DevelopColorMixer
{
    public IReadOnlyList<float> Hue { get; init; } = new float[BandCount];

    public IReadOnlyList<float> Saturation { get; init; } = new float[BandCount];

    public IReadOnlyList<float> Luminance { get; init; } = new float[BandCount];

    public const int BandCount = 8;
}

public readonly record struct DevelopColorGradeRegion(
    float Hue,
    float Saturation,
    float Luminance);

/// <summary>macOS Color Grading의 세 tonal range와 공통 조정 값입니다.</summary>
public sealed class DevelopColorGrading
{
    public DevelopColorGradeRegion Shadows { get; init; }

    public DevelopColorGradeRegion Midtones { get; init; }

    public DevelopColorGradeRegion Highlights { get; init; }

    public float Blending { get; init; } = 0.5F;

    public float Balance { get; init; }
}

public sealed class DevelopExportRequest
{
    public required string SourcePath { get; init; }

    public required string DestinationPath { get; init; }

    public DevelopExportFormat Format { get; init; } = DevelopExportFormat.Png16;

    public NegativeFilmType FilmType { get; init; } = NegativeFilmType.Color;

    public DevelopBaseEstimationMode BaseEstimationMode { get; init; } =
        DevelopBaseEstimationMode.Manual;

    public float DminRed { get; init; }

    public float DminGreen { get; init; }

    public float DminBlue { get; init; }

    public string? FilmStockDminId { get; init; }

    public string? LightSourceProfileId { get; init; }

    public float ExposureStops { get; init; }

    public float Contrast { get; init; }

    public float Density { get; init; }

    public float Highlight { get; init; }

    public float Shadow { get; init; }

    public float Whites { get; init; }

    public float Blacks { get; init; }

    public float Highlights { get; init; }

    public float Lights { get; init; }

    public float Darks { get; init; }

    public float Shadows { get; init; }

    public DevelopPointCurves PointCurves { get; init; } = new();

    public DevelopColorMixer ColorMixer { get; init; } = new();

    public DevelopColorGrading ColorGrading { get; init; } = new();

    public DevelopSourceKind FilmLookSourceKind { get; init; } = DevelopSourceKind.FilmScan;

    public FilmEmulationProfile FilmEmulation { get; init; } = FilmEmulationProfile.None;

    public double FilmEmulationIntensity { get; init; } = 0.5;

    public uint RowsPerCopy { get; init; } = 64;
}

public sealed class DevelopExportResult
{
    internal DevelopExportResult(
        bool succeeded,
        DevelopExportStage failedStage,
        string failureName,
        uint nativeErrorCode,
        uint cleanupErrorCode,
        uint imageWidth,
        uint imageHeight,
        FilmLookRoute filmLookRoute,
        bool filmLookColorApplied,
        bool filmLookAcutanceApplied,
        ulong sourceFileBytes,
        ulong outputFileBytes,
        ulong filmLookWorkspaceBytes,
        ulong wallMicroseconds,
        float appliedDminRed = 0,
        float appliedDminGreen = 0,
        float appliedDminBlue = 0,
        DevelopBaseSource baseSource = DevelopBaseSource.Manual)
    {
        Succeeded = succeeded;
        FailedStage = failedStage;
        FailureName = failureName;
        NativeErrorCode = nativeErrorCode;
        CleanupErrorCode = cleanupErrorCode;
        ImageWidth = imageWidth;
        ImageHeight = imageHeight;
        FilmLookRoute = filmLookRoute;
        FilmLookColorApplied = filmLookColorApplied;
        FilmLookAcutanceApplied = filmLookAcutanceApplied;
        SourceFileBytes = sourceFileBytes;
        OutputFileBytes = outputFileBytes;
        FilmLookWorkspaceBytes = filmLookWorkspaceBytes;
        WallMicroseconds = wallMicroseconds;
        AppliedDminRed = appliedDminRed;
        AppliedDminGreen = appliedDminGreen;
        AppliedDminBlue = appliedDminBlue;
        BaseSource = baseSource;
    }

    public bool Succeeded { get; }

    public DevelopExportStage FailedStage { get; }

    /// <summary>
    /// The stage's own status name, not a translated message. Stable enough to log,
    /// switch on, and put in a bug report.
    /// </summary>
    public string FailureName { get; }

    public uint NativeErrorCode { get; }

    public uint CleanupErrorCode { get; }

    public uint ImageWidth { get; }

    public uint ImageHeight { get; }

    public FilmLookRoute FilmLookRoute { get; }

    public bool FilmLookColorApplied { get; }

    public bool FilmLookAcutanceApplied { get; }

    public ulong SourceFileBytes { get; }

    public ulong OutputFileBytes { get; }

    public ulong FilmLookWorkspaceBytes { get; }

    public ulong WallMicroseconds { get; }

    public float AppliedDminRed { get; }

    public float AppliedDminGreen { get; }

    public float AppliedDminBlue { get; }

    public DevelopBaseSource BaseSource { get; }
}
