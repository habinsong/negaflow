namespace Negaflow.Catalog;

/// <summary>macOS <c>BWToningMode</c> 와 같은 세 가지입니다. 저장 문자열도 같습니다.</summary>
public enum BwToningMode
{
    None,
    Selenium,
    Sepia,
}

/// <summary>
/// 흑백 토닝입니다. macOS <c>BWToning</c> 과 같은 네 값이며 흑백 필름에서만 걸립니다.
/// </summary>
/// <remarks>
/// 색조 두 값은 각도(0...360)이고 모드마다 기본값이 다릅니다. 키가 없을 때 0 이 아니라 그
/// 모드의 기본 색조를 쓰는 것이 macOS 와 같은 점이며, 0 으로 두면 선택하자마자 빨강으로
/// 물드는 전혀 다른 그림이 나옵니다.
/// </remarks>
public readonly record struct BwToningRecipe(
    BwToningMode Mode,
    double ShadowHue,
    double HighlightHue,
    double Strength)
{
    public static BwToningRecipe None { get; } = For(BwToningMode.None);

    /// <summary>모드만 정하고 색조는 그 모드의 기본값을 쓰는 recipe 입니다.</summary>
    public static BwToningRecipe For(BwToningMode mode, double strength = 0.0) =>
        new(mode, DefaultShadowHue(mode), DefaultHighlightHue(mode), strength);

    public static double DefaultShadowHue(BwToningMode mode) =>
        mode == BwToningMode.Sepia ? 32.0 : 285.0;

    public static double DefaultHighlightHue(BwToningMode mode) =>
        mode == BwToningMode.Sepia ? 48.0 : 34.0;

    /// <summary>macOS 가 모드를 켤 때 쓰는 최소 세기입니다. 0 이면 켜도 아무 일이 없습니다.</summary>
    public const double EngagedStrength = 0.45;

    public double ClampedStrength => Math.Clamp(Strength, 0.0, 1.0);

    public bool IsIdentity => Mode == BwToningMode.None || ClampedStrength <= 1e-4;

    public bool IsValid =>
        Enum.IsDefined(Mode) &&
        double.IsFinite(ShadowHue) && ShadowHue is >= 0.0 and <= 360.0 &&
        double.IsFinite(HighlightHue) && HighlightHue is >= 0.0 and <= 360.0 &&
        double.IsFinite(Strength) && Strength is >= 0.0 and <= 1.0;

    /// <summary>macOS 처럼 각도를 0...360 으로 감습니다.</summary>
    public static double NormalizeHue(double hue)
    {
        if (!double.IsFinite(hue))
        {
            return 0.0;
        }
        // Swift 의 truncatingRemainder 와 같은 나머지입니다. IEEERemainder 는 가장 가까운
        // 배수로 반올림해 190도를 -170도로 만들어 버립니다.
        double wrapped = hue % 360.0;
        if (wrapped < 0.0)
        {
            wrapped += 360.0;
        }
        return wrapped;
    }
}
