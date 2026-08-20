namespace Negaflow.Catalog;

/// <summary>
/// 수동 base picker 결과입니다. macOS 의 <c>params.manualBaseRGB</c> 와 같은 자리이며 세 채널
/// 배열로 저장됩니다. 값이 없으면 Auto 모드에서 native scene-edge base 추정으로 갑니다. 이 값은
/// Auto 추정의 입력으로 대신 쓰지 않습니다.
/// </summary>
public readonly record struct ManualBaseRgb(double Red, double Green, double Blue);

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
    /// 사용자가 적어 둔 제목·설명·키워드·저작권과 촬영 기록입니다. 원본 파일이 아니라
    /// 카탈로그에만 살며, 적은 적이 없으면 null 입니다.
    /// </summary>
    public AppMetadataOverlay? AppMetadata { get; init; }

    /// <summary>
    /// macOS <c>ScanFrame.baseRGB</c> — 마지막 현상이 쓴 Dmin 입니다. 카탈로그
    /// <c>baseRGB</c> 에 남고, 수동 샘플 <see cref="ManualBase"/> 와는 자리가 다릅니다.
    /// </summary>
    public ManualBaseRgb? AppliedBase { get; init; }

    /// <summary>
    /// 결함 검토를 마쳤을 때의 recipe 판입니다. macOS
    /// <c>LibraryDefectReviewTracking.reviewed*</c> 셋과 같습니다. 지금 recipe 와 세 값이
    /// 모두 같아야 "검토 완료"입니다.
    /// </summary>
    public DefectReviewMarkRecord? DefectReviewMark { get; init; }

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

    /// <summary>
    /// 현상 기록입니다. macOS <c>ScanFrame.developHistory</c> · 사이드카 <c>developHistory</c> 와
    /// 같은 자리이며 스냅샷과 모양이 같습니다 — 다른 것은 목록 이름과 쓰임뿐입니다.
    /// </summary>
    public IReadOnlyList<LibraryVersionSnapshot> History { get; init; } = [];

    public TextureRecipe Texture { get; init; } = TextureRecipe.Identity;

    public NoiseReductionRecipe NoiseReduction { get; init; } = NoiseReductionRecipe.Identity;

    /// <summary>흑백 토닝입니다. 컬러 필름에서는 엔진이 무시하므로 값만 보존합니다.</summary>
    public BwToningRecipe BwToning { get; init; } = BwToningRecipe.None;

    /// <summary>
    /// 전체 프레임 자동 GrainMend 세기입니다. macOS <c>params.defectRemoval</c> 과 같은 자리이며,
    /// macOS 앱 UI 는 이 값을 직접 내놓지 않고 CLI·프리셋·붙여넣기로만 옵니다. 값을 버리면
    /// 그런 경로로 들어온 frame 이 Windows 에서 다르게 현상됩니다.
    /// </summary>
    public double DefectRemovalStrength { get; init; }

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

    /// <summary>롤 안에서의 순번입니다(1부터). macOS <c>scanIndex</c> 와 같은 자리입니다.</summary>
    public int ScanIndex { get; init; }

    /// <summary>스캐너가 낸 것인지 사용자가 가져온 것인지. 이름 짓는 방식이 달라집니다.</summary>
    public FrameSourceKind SourceKind { get; init; } = FrameSourceKind.ImportedFile;

    /// <summary>
    /// 가상 사본이 물려받은 원본의 이름입니다. macOS 만 적으며, 있으면 파일 이름보다 앞섭니다.
    /// </summary>
    public string? SourceFrameDisplayName { get; init; }

    /// <summary>
    /// 이 사진이 가상 사본이면 원본 사진의 id 입니다. 원본 자신은 null 이며, 그때 가족의
    /// 뿌리는 자기 자신입니다.
    /// </summary>
    public string? SourceFrameId { get; init; }

    /// <summary>가상 사본 번호입니다(1부터). 원본은 null 입니다.</summary>
    public int? VirtualCopyNumber { get; init; }

    /// <summary>가상 사본인지. macOS <c>isVirtualCopy</c> 와 같습니다.</summary>
    public bool IsVirtualCopy => VirtualCopyNumber is not null;

    /// <summary>
    /// 같은 원본을 나눠 쓰는 가족의 뿌리 id 입니다 — macOS <c>rootFrameID</c> 와 같습니다.
    /// 사본의 사본을 만들어도 뿌리는 하나로 유지됩니다.
    /// </summary>
    public string RootFrameId => SourceFrameId ?? Id;

    /// <summary>
    /// 사용자가 "이름 변경"으로 지정한 사진 번호입니다. macOS 는 이 값을
    /// <c>customDisplayName</c> 안에 <c>negaflow:photo-number:</c> 표식으로 넣어 두므로, 표식을
    /// 모르면 카드에 그 문자열이 그대로 나옵니다.
    /// </summary>
    public int? AssignedPhotoNumber =>
        DisplayName is { } name && name.StartsWith(AssignedPhotoNumberPrefix, StringComparison.Ordinal) &&
        int.TryParse(
            name.AsSpan(AssignedPhotoNumberPrefix.Length),
            System.Globalization.NumberStyles.None,
            System.Globalization.CultureInfo.InvariantCulture,
            out int number) &&
        number > 0
            ? number
            : null;

    /// <summary>사용자가 직접 지은 이름입니다. 번호 표식은 이름이 아니므로 제외합니다.</summary>
    public string? LiteralDisplayName =>
        AssignedPhotoNumber is not null || string.IsNullOrWhiteSpace(DisplayName)
            ? null
            : DisplayName.Trim();

    /// <summary>
    /// 카드에 붙는 번호입니다. 지정한 번호가 있으면 그것을, 스캐너 파일이면 파일 이름 끝의
    /// <c>_frame_&lt;n&gt;</c> 을, 아니면 롤 순번을 씁니다 — macOS <c>presentationIndex</c> 와
    /// 같은 차례입니다.
    /// </summary>
    public int PresentationIndex
    {
        get
        {
            if (AssignedPhotoNumber is { } assigned)
            {
                return assigned;
            }
            if (SourceKind != FrameSourceKind.ScannerTiff)
            {
                return ScanIndex;
            }
            string baseName = Path.GetFileNameWithoutExtension(SourcePath);
            int marker = baseName.LastIndexOf("_frame_", StringComparison.Ordinal);
            if (marker < 0)
            {
                return ScanIndex;
            }
            ReadOnlySpan<char> suffix = baseName.AsSpan(marker + "_frame_".Length);
            return !suffix.IsEmpty &&
                int.TryParse(
                    suffix,
                    System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out int fileIndex) &&
                fileIndex > 0
                    ? fileIndex
                    : ScanIndex;
        }
    }

    /// <summary>
    /// 번호를 붙이지 않고 그대로 쓸 이름입니다. 없으면 호출자가 번호로 이름을 지어야 합니다 —
    /// 그 문구는 언어마다 다르므로 셸이 만듭니다.
    /// </summary>
    public string? PreferredBaseDisplayName =>
        UsableLiteralDisplayName
            ?? (string.IsNullOrWhiteSpace(SourceFrameDisplayName)
                ? null
                : SourceFrameDisplayName.Trim())
            ?? (SourceKind == FrameSourceKind.ImportedFile ? SourceFileBaseName : null);

    /// <summary>
    /// 사용자가 붙인 이름입니다. 단, **예전 Windows 가져오기가 남긴 `이름.확장자`** 는 이름이
    /// 아니라 버그의 흔적이므로 무시합니다.
    ///
    /// ☠️ macOS 는 가져오기에서 `customDisplayName` 을 아예 쓰지 않고 확장자를 뗀 파일 이름으로
    ///    물러납니다. Windows 가 한때 `Path.GetFileName` 을 그대로 적어 넣어서, 카드·필름스트립·
    ///    창 제목이 `이름.tiff` 가 되고 내보내기 파일명이 `이름.tiff.jpg` 로 나왔습니다.
    ///    가져오기는 고쳤지만 이미 적힌 줄은 남아 있으므로, **원본 파일 이름과 글자까지 같은**
    ///    값일 때만 물러납니다 — 사용자가 직접 붙인 다른 이름은 그대로 지킵니다.
    /// </summary>
    private string? UsableLiteralDisplayName =>
        LiteralDisplayName is { } literal &&
        !string.Equals(literal, Path.GetFileName(SourcePath), StringComparison.Ordinal)
            ? literal
            : null;

    /// <summary>확장자를 뗀 원본 파일 이름입니다. macOS <c>sourceFileBaseName</c> 과 같습니다.</summary>
    public string? SourceFileBaseName =>
        Path.GetFileNameWithoutExtension(SourcePath).Trim() is { Length: > 0 } name
            ? name
            : null;

    /// <summary>
    /// 번역이 닿지 않는 자리(로그, 진단)에서 쓰는 이름입니다. 화면에 보이는 이름은
    /// <c>LibraryFrameNaming</c> 이 언어에 맞춰 짓습니다.
    /// </summary>
    public string EffectiveDisplayName =>
        PreferredBaseDisplayName ?? Path.GetFileName(SourcePath);

    internal const string AssignedPhotoNumberPrefix = "negaflow:photo-number:";

    /// <summary>
    /// 번호 표식입니다. macOS 가 <c>customDisplayName</c> 에 적는 것과 **글자 하나까지 같아야**
    /// 두 앱이 같은 사진을 같은 번호로 부릅니다.
    /// </summary>
    public static string AssignedPhotoNumberPrefixValue => AssignedPhotoNumberPrefix;
}

/// <summary>macOS <c>FrameSource</c> 와 같습니다. catalog 에는 문자열로 삽니다.</summary>
public enum FrameSourceKind
{
    ScannerTiff,
    ImportedFile,
}
