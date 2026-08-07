namespace Negaflow.Catalog;

/// <summary>
/// 수동 base picker 결과입니다. macOS 의 <c>params.manualBaseRGB</c> 와 같은 자리이며 세 채널
/// 배열로 저장됩니다. 값이 없으면 macOS 는 auto base 추정으로 갑니다. **Windows 에는 아직 auto
/// 추정이 없으므로** 없는 것을 0 이나 임의값으로 채우지 않고 없는 채로 돌려줍니다.
/// </summary>
public readonly record struct ManualBaseRgb(double Red, double Green, double Blue);

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
    double CurveShadows)
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
    /// 수동 Dmin 이 없으면 현상할 수 없습니다. auto base 추정이 생기기 전까지는 이것이 사실이므로
    /// 기본값을 지어내지 않고 그대로 드러냅니다.
    /// </summary>
    public bool CanDevelop => ManualBase is not null;

    public string EffectiveDisplayName =>
        string.IsNullOrWhiteSpace(DisplayName)
            ? Path.GetFileName(SourcePath)
            : DisplayName;
}
