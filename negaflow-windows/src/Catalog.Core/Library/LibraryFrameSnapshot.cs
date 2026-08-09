namespace Negaflow.Catalog;

/// <summary>
/// 수동 base picker 결과입니다. macOS 의 <c>params.manualBaseRGB</c> 와 같은 자리이며 세 채널
/// 배열로 저장됩니다. 값이 없으면 Auto 모드에서 native scene-edge base 추정으로 갑니다. 이 값은
/// Auto 추정의 입력으로 대신 쓰지 않습니다.
/// </summary>
public readonly record struct ManualBaseRgb(double Red, double Green, double Blue);

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
    /// macOS-compatible base mode and preset identifiers. This is persisted independently
    /// from <see cref="ManualBase"/> because changing modes does not erase a manual sample.
    /// </summary>
    public BaseRecipe Base { get; init; } = BaseRecipe.Auto;

    /// <summary>
    /// Point Curve는 Basic/Parametric Tone 값과 분리된 macOS recipe입니다. 빈 채널은 identity입니다.
    /// </summary>
    public PointCurveRecipe PointCurves { get; init; } = PointCurveRecipe.Identity;

    /// <summary>macOS Color Mixer의 HSL 8밴드 recipe입니다.</summary>
    public ColorMixerRecipe ColorMixer { get; init; } = ColorMixerRecipe.Identity;

    /// <summary>
    /// Auto는 native resolver가 입력에서 base를 결정하므로 수동 Dmin 없이 현상할 수 있습니다.
    /// Manual만 저장된 수동 base를 요구하고, 아직 resolver가 없는 Preset은 명시적으로 막습니다.
    /// </summary>
    public bool CanDevelop =>
        (Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative) &&
        (Base.Mode switch
        {
            BaseEstimationMode.Auto => true,
            BaseEstimationMode.Preset => !string.IsNullOrWhiteSpace(Base.FilmStockDminId),
            BaseEstimationMode.Manual => ManualBase is not null,
            _ => false,
        });

    public string EffectiveDisplayName =>
        string.IsNullOrWhiteSpace(DisplayName)
            ? Path.GetFileName(SourcePath)
            : DisplayName;
}
