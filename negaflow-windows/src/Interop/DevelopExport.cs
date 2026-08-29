namespace Negaflow.Interop;

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

    /// <summary>
    /// Ordered render-affecting Defects recipe SHA-256. Native preview caches use it only
    /// as an exact invalidation identity; the projected recipe remains authoritative.
    /// </summary>
    public string? DefectRecipeSha256 { get; init; }

    /// <summary>
    /// 마지막 ordered edit를 제외한 canonical recipe SHA-256입니다. Native는 보유한 cleaned raw의
    /// recipe identity와 정확히 일치할 때만 suffix 적용에 사용합니다.
    /// </summary>
    public string? DefectRecipeAppendPrefixSha256 { get; init; }

    public int DefectRecipeAppendPrefixEditCount { get; init; }

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
    /// 인화소가 준 ICC 프로파일입니다. 비어 있지 않으면 <b>이것이 게시 색공간</b>이 되어
    /// <see cref="OutputColorSpace"/> 를 대신합니다 — 화소를 이 프로파일로 옮기고 파일에도
    /// 이것을 박습니다. macOS <c>ExportEngine.write(outputProfile:)</c> 와 같은 뜻입니다.
    /// </summary>
    public byte[]? OutputIccProfile { get; init; }

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

    /// <summary>
    /// 이 결과가 <b>인화 판에 얹힐 프록시</b>일 때, 원본을 얼마나 크게 풀지입니다. 0 이면
    /// 원본 그대로 — 사용자에게 나가는 내보내기는 전부 0 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="OutputLongEdge"/> 는 <b>다 만든 뒤</b> 줄이는 상한이고 이것은 <b>풀 때</b>
    /// 의 상한입니다. macOS 는 판을 만들 때
    /// <c>ExportDevelopedFrameRenderer.proxyInputLongEdge(outputLongEdge:…)</c> 로 이 값을
    /// 구해 <c>prepareForPrintComposite(_:proxyLongEdge:)</c> 에 넘깁니다 — 콘택트 시트 한
    /// 칸이 268 px 인데 5136x3543 을 통째로 푸는 일이 맥에는 없는 이유입니다.
    /// </remarks>
    public uint ProxyInputLongEdge { get; init; }

    public uint RowsPerCopy { get; init; } = 64;
}
