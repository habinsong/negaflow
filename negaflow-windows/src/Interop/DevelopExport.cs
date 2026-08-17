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

public readonly record struct DevelopCropRect(
    double X,
    double Y,
    double Width,
    double Height);

public sealed class DevelopImageTransform
{
    public DevelopImageRotation Rotation { get; init; }

    public bool FlipHorizontal { get; init; }

    public bool FlipVertical { get; init; }

    /// <summary>macOS와 동일한 y-up 정규화 좌표입니다. null이면 전체 프레임입니다.</summary>
    public DevelopCropRect? Crop { get; init; }

    public double StraightenAngle { get; init; }
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
    TriX400 = 12,
    Hp5Plus = 13,
    Fp4Plus = 14,
    Delta100 = 15,
    Delta400 = 16,
    Delta3200 = 17,
    TMax100 = 18,
    TMax400 = 19,
    TMaxP3200 = 20,
    Kentmere400 = 21,
    OrthoPlus = 22,
    Sfx200 = 23,
    RolleiIR = 24,
    Scala200X = 25,
    RolleiSuperpan = 26,
    Velvia100 = 27,
    E100VS = 28,
    Astia100F = 29,
    Kodachrome64 = 30,
    Gold200 = 31,
    ProImage100 = 32,
    Superia400 = 33,
    SuperiaPremium400 = 34,
    Superia200 = 35,
    Reala100 = 36,
    Industrial100 = 37,
    LomoCn800 = 38,
    Vision3_500T = 39,
    Vision3_250D = 40,
    Vision3_50D = 41,
    Vision3_200T = 42,
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
    GrainMend = 10,
    FilmScanDenoise = 11,
    LocalDodgeBurn = 12,
    Texture = 13,
    BlackAndWhite = 14,
    ImageTransform = 15,
    ColorModel = 16,
    SceneCorrection = 17,
    TargetGrade = 18,
    DefectComponentRepair = 19,
    DefectCloneStamp = 20,
    DefectBrush = 21,
    OutputSharpening = 22,
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

public sealed class DevelopPrimaryCalibration
{
    public float RedHue { get; init; }
    public float RedSaturation { get; init; }
    public float GreenHue { get; init; }
    public float GreenSaturation { get; init; }
    public float BlueHue { get; init; }
    public float BlueSaturation { get; init; }
}

public enum DevelopLocalDodgeBurnMode
{
    Dodge = 0,
    Burn = 1,
}

public enum DevelopLocalDodgeBurnMaskKind
{
    Brush = 0,
    Radial = 1,
    Linear = 2,
    Polygon = 3,
}

public readonly record struct DevelopLocalDodgeBurnPoint(double X, double Y);

public sealed class DevelopLocalDodgeBurnStroke
{
    public IReadOnlyList<DevelopLocalDodgeBurnPoint> Points { get; init; } = [];

    public double Thickness { get; init; } = 0.04;

    public double Feather { get; init; } = 0.02;
}

public sealed class DevelopLocalDodgeBurnMask
{
    public DevelopLocalDodgeBurnMaskKind Kind { get; init; }

    public IReadOnlyList<DevelopLocalDodgeBurnStroke> Strokes { get; init; } = [];

    public DevelopLocalDodgeBurnPoint Center { get; init; } = new(0.5, 0.5);

    public double Radius { get; init; } = 0.25;

    public double Feather { get; init; } = 0.25;

    public DevelopLocalDodgeBurnPoint Start { get; init; } = new(0.5, 0.0);

    public DevelopLocalDodgeBurnPoint End { get; init; } = new(0.5, 1.0);

    public IReadOnlyList<DevelopLocalDodgeBurnPoint> Points { get; init; } = [];
}

public sealed class DevelopLocalDodgeBurnAdjustment
{
    public DevelopLocalDodgeBurnMode Mode { get; init; }

    public double Amount { get; init; }

    public bool IsEnabled { get; init; } = true;

    public DevelopLocalDodgeBurnMask Mask { get; init; } = new();
}

/// <summary>
/// 현상 전 linear raw에 순서대로 적용되는 macOS 영역 Defects 레이어입니다.
/// ROI는 raw 픽셀의 y-up 좌표이고, 마스크의 첫 행은 ROI의 위쪽입니다.
/// </summary>
public sealed class DevelopDefectRegionEdit
{
    public bool IsEnabled { get; init; } = true;

    public uint RoiX { get; init; }

    public uint RoiY { get; init; }

    public uint Width { get; init; }

    public uint Height { get; init; }

    public uint MaskStrideBytes { get; init; }

    public ReadOnlyMemory<byte> Mask { get; init; }

    public double Strength { get; init; } = 1.0;

    public double? PreferredAngleDegrees { get; init; }
}

public sealed class DevelopDefectInfraredCluster
{
    public uint RoiX { get; init; }

    public uint RoiY { get; init; }

    public uint Width { get; init; }

    public uint Height { get; init; }

    public uint CoreMaskStrideBytes { get; init; }

    public ReadOnlyMemory<byte> CoreMask { get; init; }

    public uint AttenuationStrideBytes { get; init; }

    public ReadOnlyMemory<byte>? AttenuationR16 { get; init; }

}

public sealed class DevelopDefectInfraredEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectInfraredCluster> Clusters { get; init; } = [];
}

public enum DevelopDefectEditKind
{
    Region,
    Clone,
    Brush,
    Infrared,
}

public readonly record struct DevelopDefectRecipeEditRef(
    DevelopDefectEditKind Kind,
    uint Index);

public readonly record struct DevelopDefectClonePoint(double X, double Y);

public sealed class DevelopDefectCloneStroke
{
    public IReadOnlyList<DevelopDefectClonePoint> Points { get; init; } = [];

    public double OffsetX { get; init; }

    public double OffsetY { get; init; }

    public double DiameterPixels { get; init; }

    public double Hardness { get; init; }
}

public sealed class DevelopDefectCloneEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectCloneStroke> Strokes { get; init; } = [];
}

public readonly record struct DevelopDefectBrushPoint(double X, double Y);

public sealed class DevelopDefectBrushStroke
{
    public IReadOnlyList<DevelopDefectBrushPoint> Points { get; init; } = [];

    /// <summary>Raw 이미지 짧은 변에 대한 브러시 굵기 비율입니다.</summary>
    public double Thickness { get; init; }
}

public sealed class DevelopDefectBrushEdit
{
    public bool IsEnabled { get; init; } = true;

    public double Strength { get; init; } = 1.0;

    public IReadOnlyList<DevelopDefectBrushStroke> Strokes { get; init; } = [];
}

/// <summary>Defects recipe가 결합된 원본 파일의 경로 독립 byte identity입니다.</summary>
public sealed record DevelopDefectSourceIdentity(ulong ByteCount, string Sha256);

/// <summary>
/// GrainMend 자동·가이드가 받아 가는 판정입니다. 마스크는 호출부 버퍼에 담기고 여기에는
/// 그 크기와 채택 화소 수만 옵니다.
/// </summary>
/// <param name="Width">검출 이미지 크기입니다. 원본 해상도가 아니라 1800 상한이 걸린 값입니다.</param>
/// <param name="MaskByteCount">
/// 마스크에 필요한 바이트 수입니다. 버퍼가 모자라 실패했을 때도 채워지므로, 이 값으로
/// 다시 부르면 됩니다.
/// </param>
/// <summary>
/// 검출기가 고른 물리 결함 종류입니다. 값은 네이티브
/// <c>grain_mend_detail::DefectClassification</c> 과 같은 순서여야 합니다 — 순서가 어긋나면
/// 분류가 통째로 밀립니다.
/// </summary>
public enum GrainMendDefectClass
{
    Dust = 0,
    Pinhole = 1,
    ScratchHorizontal = 2,
    ScratchVertical = 3,
    ScratchDiagonal = 4,
    EmulsionDamage = 5,
    MicroSpeck = 6,
}

/// <summary>
/// 채택된 결함 하나입니다. 좌표는 검출 이미지
/// (<see cref="GrainMendDetectionResult.Width"/>×<see cref="GrainMendDetectionResult.Height"/>)
/// 기준입니다.
/// </summary>
public readonly record struct GrainMendComponent(
    GrainMendDefectClass Classification,
    double Confidence,
    ulong Area,
    uint MinimumX,
    uint MinimumY,
    uint MaximumX,
    uint MaximumY,
    IReadOnlyList<GrainMendPreviewPoint>? PreviewPoints = null)
{
    /// <summary>
    /// 이 결함을 화면에 표시할 점들입니다. macOS <c>previewComponents</c> 와 같은 규칙으로
    /// 솎여 있습니다 — 전체 예산 24,000 점, 컴포넌트당 최대 800 점.
    /// </summary>
    public IReadOnlyList<GrainMendPreviewPoint> Points => PreviewPoints ?? [];
}

/// <summary>검출 이미지 기준 좌표입니다(원본 화소가 아닙니다).</summary>
public readonly record struct GrainMendPreviewPoint(uint X, uint Y);

public readonly record struct GrainMendDetectionResult(
    DevelopExportResult Result,
    uint Width,
    uint Height,
    ulong AcceptedPixels,
    ulong MaskByteCount,
    uint SourceWidth = 0U,
    uint SourceHeight = 0U,
    uint RoiX = 0U,
    uint RoiY = 0U,
    uint RoiWidth = 0U,
    uint RoiHeight = 0U,
    IReadOnlyList<GrainMendComponent>? Components = null,
    // macOS `DefectLabelField.automaticFalsePositiveRisk` /
    // `automaticCandidatePixelFraction`. 전체 프레임 자동에서만 채워지고, 성분은 하나도
    // 버리지 않습니다 — 화면이 개수 대신 경고 문구를 낼 뿐입니다.
    bool AutomaticFalsePositiveRisk = false,
    double AutomaticCandidatePixelFraction = 0.0)
{
    /// <summary>
    /// 채택된 결함 하나하나. 비어 있으면 분류가 없는 것이며, 지어내지 않습니다.
    /// </summary>
    public IReadOnlyList<GrainMendComponent> Defects => Components ?? [];
}

/// <summary>
/// GrainMend 자동·가이드 검토에서만 쓰는 일회성 검출기 설정입니다. 수락 전 후보를 바꿀 뿐
/// Defects sidecar나 일반 현상 레시피에는 기록되지 않습니다.
/// </summary>
public readonly record struct GrainMendDetectionOptions(
    double DustSensitivity,
    double ScratchSensitivity,
    double ProtectDetail,
    bool RejectStructureLines,
    bool DetectMicroSpecks)
{
    // The historical entry point did not expose the extra pass. Keep an omitted
    // option backward compatible; the review UI explicitly follows macOS and enables it.
    public static GrainMendDetectionOptions LegacyDefault { get; } = new(0.5, 0.5, 0.75, false, false);
}

public sealed class DevelopExportRequest
{
    public required string SourcePath { get; init; }

    public required string DestinationPath { get; init; }

    public DevelopExportFormat Format { get; init; } = DevelopExportFormat.Png16;

    public NegativeFilmType FilmType { get; init; } = NegativeFilmType.Color;

    public FilmPolarity FilmPolarity { get; init; } = FilmPolarity.Negative;

    public DevelopBaseEstimationMode BaseEstimationMode { get; init; } =
        DevelopBaseEstimationMode.Manual;

    public float DminRed { get; init; }

    public float DminGreen { get; init; }

    public float DminBlue { get; init; }

    public string? FilmStockDminId { get; init; }

    public string? LightSourceProfileId { get; init; }

    public string? ScannerProfileId { get; init; }

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

    public float Warmth { get; init; }

    public float Tint { get; init; }

    public float ColorDepth { get; init; }

    public float Vibrance { get; init; }

    public float Saturation { get; init; }

    public float RedPrimary { get; init; }

    public float GreenPrimary { get; init; }

    public float BluePrimary { get; init; }

    public bool AutoLevels { get; init; }

    public bool AutoNeutralBalance { get; init; }

    public DevelopTargetMode DevelopTarget { get; init; }

    public DevelopPointCurves PointCurves { get; init; } = new();

    public DevelopColorMixer ColorMixer { get; init; } = new();

    public DevelopColorGrading ColorGrading { get; init; } = new();

    public DevelopPrimaryCalibration PrimaryCalibration { get; init; } = new();

    public DevelopSourceKind FilmLookSourceKind { get; init; } = DevelopSourceKind.FilmScan;

    public FilmEmulationProfile FilmEmulation { get; init; } = FilmEmulationProfile.None;

    public double FilmEmulationIntensity { get; init; } = 0.5;

    /// <summary>RGB-only GrainMend automatic repair strength from zero through one.</summary>
    public double DefectRemovalStrength { get; init; }

    public IReadOnlyList<DevelopDefectRegionEdit> DefectRegions { get; init; } = [];

    public IReadOnlyList<DevelopDefectInfraredEdit> DefectInfrared { get; init; } = [];

    public IReadOnlyList<DevelopDefectCloneEdit> DefectClones { get; init; } = [];

    public IReadOnlyList<DevelopDefectBrushEdit> DefectBrushes { get; init; } = [];

    public IReadOnlyList<DevelopDefectRecipeEditRef> DefectEditOrder { get; init; } = [];

    public DevelopDefectSourceIdentity? DefectSourceIdentity { get; init; }

    /// <summary>FilmScanDenoise master strength from zero through one.</summary>
    public float NoiseReductionStrength { get; init; }

    public float NoiseReductionLuma { get; init; } = 0.5F;

    public float NoiseReductionChroma { get; init; } = 0.5F;

    public float NoiseReductionDarkTone { get; init; } = 0.5F;

    public float NoiseReductionDetail { get; init; } = 0.5F;

    public float NoiseReductionGrainProtect { get; init; }

    public FilmScanDenoiseFilmProfile NoiseReductionFilmProfile { get; init; } =
        FilmScanDenoiseFilmProfile.ColorNegative;

    public IReadOnlyList<DevelopLocalDodgeBurnAdjustment> LocalDodgeBurn { get; init; } = [];

    public float Grain { get; init; }

    public float Sharpness { get; init; }

    public float Halation { get; init; }

    public float Clarity { get; init; }

    public float Vignette { get; init; }

    public BwToningMode BwToningMode { get; init; }

    /// <summary>null이면 macOS와 같이 선택된 모드의 기본 hue를 사용합니다.</summary>
    public double? BwToningShadowHue { get; init; }

    /// <summary>null이면 macOS와 같이 선택된 모드의 기본 hue를 사용합니다.</summary>
    public double? BwToningHighlightHue { get; init; }

    public double BwToningStrength { get; init; }

    public DevelopImageTransform ImageTransform { get; init; } = new();

    /// <summary>Final output-only unsharp strength from zero through one.</summary>
    public float OutputSharpening { get; init; }

    public OutputSharpeningMedium OutputSharpeningMedium { get; init; } =
        OutputSharpeningMedium.Screen;

    /// <summary>Zero uses the selected medium's reference DPI.</summary>
    public int OutputSharpeningDpi { get; init; }

    /// <summary>JPEG encoding fidelity from zero through one. Other formats ignore it.</summary>
    public float JpegQuality { get; init; } = 1.0F;

    /// <summary>TIFF compression. PNG and JPEG ignore it.</summary>
    public DevelopTiffCompression TiffCompression { get; init; }

    /// <summary>
    /// Published sample depth, 8 or 16. PNG and TIFF honour it; JPEG is eight-bit by
    /// definition. Eight-bit output is dithered before quantization, as macOS does.
    /// </summary>
    public uint OutputBitDepth { get; init; } = 16U;

    /// <summary>
    /// Published colour space. PNG and TIFF convert the pixels and carry the matching
    /// profile; JPEG publishes sRGB only and refuses anything else.
    /// </summary>
    public ExportColorSpace OutputColorSpace { get; init; } = ExportColorSpace.Srgb;

    /// <summary>
    /// PNG/TIFF exports preserve straight source alpha. JPEG requests with this flag are
    /// rejected before the native pipeline reads the source.
    /// </summary>
    public bool PreserveAlpha { get; init; }

    /// <summary>
    /// What to write into the published file. PNG carries no EXIF, so the policy leaves
    /// no trace in a PNG.
    /// </summary>
    public ExportMetadataPolicy MetadataPolicy { get; init; } = ExportMetadataPolicy.Minimal;

    public ExportMetadataValues Metadata { get; init; } = new();

    /// <summary>Positive values are embedded in PNG, TIFF, and JPEG metadata and do not resize pixels.</summary>
    public uint OutputDpi { get; init; }

    /// <summary>
    /// Zero preserves source dimensions. Positive values cap only the published artifact's
    /// long edge; they never upscale or change preview and GrainMend-review geometry.
    /// </summary>
    public uint OutputLongEdge { get; init; }

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
        DevelopBaseSource baseSource = DevelopBaseSource.Manual,
        bool cancelled = false)
    {
        Cancelled = cancelled;
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

    /// <summary>
    /// 호출자가 <see cref="DevelopRun.Cancel"/> 로 멈춘 실행입니다. 실패와 구분해야 하며,
    /// 취소된 실행은 파일도 미리보기 픽셀도 남기지 않습니다.
    /// </summary>
    public bool Cancelled { get; }

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
