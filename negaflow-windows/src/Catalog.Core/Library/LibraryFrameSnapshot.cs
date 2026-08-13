namespace Negaflow.Catalog;

/// <summary>
/// 수동 base picker 결과입니다. macOS 의 <c>params.manualBaseRGB</c> 와 같은 자리이며 세 채널
/// 배열로 저장됩니다. 값이 없으면 Auto 모드에서 native scene-edge base 추정으로 갑니다. 이 값은
/// Auto 추정의 입력으로 대신 쓰지 않습니다.
/// </summary>
public readonly record struct ManualBaseRgb(double Red, double Green, double Blue);

/// <summary>
/// macOS <c>ImageTransform</c>와 같은 회전 값입니다. 저장값은 Swift recipe의 raw value와
/// 같고, crop 좌표는 y-up 정규화 좌표를 사용합니다.
/// </summary>
public enum ImageRotation
{
    Degrees0 = 0,
    Degrees90 = 1,
    Degrees180 = 2,
    Degrees270 = 3,
}

public readonly record struct ImageCropRect(double X, double Y, double Width, double Height)
{
    public bool IsValid =>
        double.IsFinite(X) && double.IsFinite(Y) &&
        double.IsFinite(Width) && double.IsFinite(Height) &&
        X >= 0.0 && Y >= 0.0 && Width > 0.0 && Height > 0.0 &&
        X + Width <= 1.0 && Y + Height <= 1.0;
}

/// <summary>
/// 현상과 내보내기에 공통으로 적용되는 macOS 호환 기하 보정 recipe입니다.
/// </summary>
public sealed record ImageTransformRecipe(
    ImageRotation Rotation,
    bool FlipHorizontal,
    bool FlipVertical,
    ImageCropRect? Crop,
    double StraightenAngle,
    double? CropAspect)
{
    public static ImageTransformRecipe Identity { get; } = new(
        ImageRotation.Degrees0,
        false,
        false,
        null,
        0.0,
        null);

    public bool IsValid =>
        Enum.IsDefined(Rotation) &&
        (Crop is null || Crop.Value.IsValid) &&
        double.IsFinite(StraightenAngle) && StraightenAngle is >= -45.0 and <= 45.0 &&
        (CropAspect is null || (double.IsFinite(CropAspect.Value) && CropAspect.Value > 0.0));
}

/// <summary>
/// macOS의 Texture controls입니다. grain, sharpness, halation은 0...1이고 clarity와
/// vignette는 부호 있는 조절값입니다.
/// </summary>
public sealed record TextureRecipe(
    double Grain,
    double Sharpness,
    double Halation,
    double Clarity,
    double Vignette)
{
    public static TextureRecipe Identity { get; } = new(0.0, 0.0, 0.0, 0.0, 0.0);

    public bool IsValid =>
        IsNormalized(Grain) && IsNormalized(Sharpness) && IsNormalized(Halation) &&
        IsSignedNormalized(Clarity) && IsSignedNormalized(Vignette);

    private static bool IsNormalized(double value) =>
        double.IsFinite(value) && value is >= 0.0 and <= 1.0;

    private static bool IsSignedNormalized(double value) =>
        double.IsFinite(value) && value is >= -1.0 and <= 1.0;
}

/// <summary>macOS FilmScanDenoise master와 다섯 축을 보존하는 recipe입니다.</summary>
public sealed record NoiseReductionRecipe(
    double Strength,
    double Luma,
    double Chroma,
    double DarkTone,
    double Detail,
    double GrainProtect)
{
    public static NoiseReductionRecipe Identity { get; } = new(0.0, 0.5, 0.5, 0.5, 0.5, 0.0);

    public bool IsValid =>
        IsNormalized(Strength) && IsNormalized(Luma) && IsNormalized(Chroma) &&
        IsNormalized(DarkTone) && IsNormalized(Detail) && IsNormalized(GrainProtect);

    private static bool IsNormalized(double value) =>
        double.IsFinite(value) && value is >= 0.0 and <= 1.0;
}

/// <summary>
/// Immutable source traits recorded when a TIFF enters the catalog.  They make a relink
/// refuse a different scan before its path can replace the original recipe input.
/// </summary>
public readonly record struct LibrarySourceMetadata(
    ulong FileBytes,
    uint PixelWidth,
    uint PixelHeight,
    ushort SamplesPerPixel,
    ushort BitsPerSample,
    ushort SampleFormat,
    ushort Orientation)
{
    public bool IsValid =>
        FileBytes > 0 && PixelWidth > 0 && PixelHeight > 0 && SamplesPerPixel > 0 &&
        BitsPerSample > 0 && SampleFormat > 0 && Orientation is >= 1 and <= 8;

    public bool IsCompatibleWith(LibrarySourceMetadata candidate) =>
        FileBytes == candidate.FileBytes &&
        PixelWidth == candidate.PixelWidth &&
        PixelHeight == candidate.PixelHeight &&
        SamplesPerPixel == candidate.SamplesPerPixel &&
        BitsPerSample == candidate.BitsPerSample &&
        SampleFormat == candidate.SampleFormat &&
        Orientation == candidate.Orientation;
}

/// <summary>
/// Base estimation recipe metadata. The catalog preserves these fields before the Windows
/// engine implements Auto and Film resolution, so UI must not expose those modes as active
/// develop paths yet.
/// </summary>
public enum BaseEstimationMode
{
    Auto,
    Preset,
    Manual,
}

/// <summary>macOS <c>FramePickState</c> 와 같은 채택 깃발입니다.</summary>
public enum FramePickState
{
    Unflagged,
    Picked,
    Rejected,
}

public enum DevelopTarget
{
    Main,
    Print,
    Noritsu,
    Sp3000,
    F135,
    Hr,
    Rescue,
}

public sealed record BaseRecipe(
    BaseEstimationMode Mode,
    string? FilmStockDminId,
    string? LightSourceProfileId,
    string? ScannerProfileId)
{
    public static BaseRecipe Auto { get; } = new(
        BaseEstimationMode.Auto,
        null,
        null,
        null);
}

/// <summary>
/// 톤 조정값입니다. 이름은 macOS <c>DevelopParameters</c> 의 key 와 같습니다. 키가 없으면 macOS 와
/// 같이 0 입니다.
/// </summary>
public readonly record struct ToneAdjustment(
    double Exposure,
    double Contrast,
    double CurveHighlights,
    double CurveLights,
    double CurveDarks,
    double CurveShadows,
    double Density = 0.0,
    double Highlight = 0.0,
    double Shadow = 0.0,
    double Whites = 0.0,
    double Blacks = 0.0)
{
    public static ToneAdjustment Neutral => default;
}

/// <summary>
/// 셸이 frame 하나를 보여 주고 현상하는 데 필요한 전부입니다. 저장소는 payload 를 해석하지 않으므로
/// 이 투영이 catalog JSON 을 읽는 유일한 자리입니다.
/// </summary>
public sealed record LibraryFrameSnapshot(
    string Id,
    string SourcePath,
    string? DisplayName,
    DevelopRouteSnapshot Route,
    ManualBaseRgb? ManualBase,
    ToneAdjustment Tone)
{
    /// <summary>
    /// Optional for catalog rows written before TIFF source preflight was introduced.
    /// Legacy rows remain readable but do not receive compatibility protection until
    /// their source metadata is known.
    /// </summary>
    public LibrarySourceMetadata? SourceMetadata { get; init; }

    /// <summary>
    /// 스캐너가 RGB 본 스캔과 함께 생성한 IR TIFF입니다. 선택적 필드라 기존 import/legacy
    /// frame은 null로 유지됩니다. 원본과 마찬가지로 현상 결과를 여기에 쓰지 않습니다.
    /// </summary>
    public string? InfraredPath { get; init; }

    /// <summary>
    /// macOS-compatible base mode and preset identifiers. This is persisted independently
    /// from <see cref="ManualBase"/> because changing modes does not erase a manual sample.
    /// </summary>
    public BaseRecipe Base { get; init; } = BaseRecipe.Auto;

    /// <summary>
    /// 이 frame 에 걸린 룩 프로파일의 id 입니다. macOS catalog 의 <c>presetID</c> 와 같은 자리이며
    /// <c>params</c> 바깥에 있습니다 — <c>params</c> 는 프리셋 위에 얹는 델타이지 최종값이 아닙니다.
    /// null 이면 프리셋 없이 <c>params</c> 가 곧 최종값입니다.
    /// </summary>
    public string? LookPresetId { get; init; }

    /// <summary>
    /// Point Curve는 Basic/Parametric Tone 값과 분리된 macOS recipe입니다. 빈 채널은 identity입니다.
    /// </summary>
    public PointCurveRecipe PointCurves { get; init; } = PointCurveRecipe.Identity;

    /// <summary>macOS Color Mixer의 HSL 8밴드 recipe입니다.</summary>
    public ColorMixerRecipe ColorMixer { get; init; } = ColorMixerRecipe.Identity;

    /// <summary>macOS Color Grading의 세 tonal range recipe입니다.</summary>
    public ColorGradingRecipe ColorGrading { get; init; } = ColorGradingRecipe.Identity;

    public PrimaryCalibrationRecipe PrimaryCalibration { get; init; } = PrimaryCalibrationRecipe.Identity;

    public IReadOnlyList<LocalDodgeBurnAdjustment> LocalDodgeBurn { get; init; } = [];

    public ColorModelRecipe ColorModel { get; init; } = ColorModelRecipe.Identity;

    public bool AutoLevels { get; init; }

    public bool AutoNeutralBalance { get; init; }

    public DevelopTarget DevelopTarget { get; init; } = DevelopTarget.Main;

    /// <summary>회전, 반전, 수평 및 crop은 preview와 export가 같은 recipe로 사용합니다.</summary>
    public ImageTransformRecipe ImageTransform { get; init; } = ImageTransformRecipe.Identity;

    /// <summary>macOS 와 같은 0...5 별점입니다. 현상에 쓰이지 않고 라이브러리 표시·정렬·필터에만 씁니다.</summary>
    public int Rating { get; init; }

    /// <summary>macOS 의 채택/제외 깃발입니다. 정렬과 필터에만 씁니다.</summary>
    public FramePickState PickState { get; init; }

    /// <summary>스캔·가져오기 시각입니다. 없는 legacy row 는 null 이며 시간순에서 뒤로 갑니다.</summary>
    public DateTimeOffset? ScannedAt { get; init; }

    /// <summary>이 frame 에 저장된 현상 버전입니다. macOS <c>developSnapshots</c> 와 같습니다.</summary>
    public IReadOnlyList<LibraryVersionSnapshot> Versions { get; init; } = [];

    public TextureRecipe Texture { get; init; } = TextureRecipe.Identity;

    public NoiseReductionRecipe NoiseReduction { get; init; } = NoiseReductionRecipe.Identity;

    /// <summary>
    /// hasDefectEdits frame에서 app-owned sidecar를 검증해 읽은 ordered recipe입니다.
    /// catalog payload 안에 mask를 중복 저장하지 않습니다.
    /// </summary>
    public DefectRecipeSnapshot? DefectRecipe { get; init; }

    /// <summary>
    /// Auto는 native resolver가 입력에서 base를 결정하므로 수동 Dmin 없이 현상할 수 있습니다.
    /// Manual만 저장된 수동 base를 요구하고, 아직 resolver가 없는 Preset은 명시적으로 막습니다.
    /// </summary>
    public bool CanDevelop => Route.SourceSignalKind switch
    {
        SourceSignalKind.RenderedDigital =>
            Route.FilmType is FilmType.ColorPositive or FilmType.BlackAndWhitePositive,
        SourceSignalKind.FilmPositiveScan =>
            Route.FilmType is FilmType.ColorPositive or FilmType.BlackAndWhitePositive,
        SourceSignalKind.FilmNegativeScan =>
            (Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative) &&
            Base.Mode switch
            {
                BaseEstimationMode.Auto => true,
                BaseEstimationMode.Preset => !string.IsNullOrWhiteSpace(Base.FilmStockDminId),
                BaseEstimationMode.Manual => ManualBase is not null,
                _ => false,
            },
        _ => false,
    };

    public string EffectiveDisplayName =>
        string.IsNullOrWhiteSpace(DisplayName)
            ? Path.GetFileName(SourcePath)
            : DisplayName;
}
