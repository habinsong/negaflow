namespace Negaflow.Catalog;

public sealed record ColorModelRecipe(
    double Warmth,
    double Tint,
    double ColorDepth,
    double Vibrance,
    double Saturation,
    double RedPrimary,
    double GreenPrimary,
    double BluePrimary)
{
    public static ColorModelRecipe Identity { get; } = new(0, 0, 0, 0, 0, 0, 0, 0);

    /// <summary>
    /// 온도·틴트의 저장 범위입니다(native <c>maximum_white_balance_control</c>, macOS
    /// <c>DevelopColorRange.whiteBalance</c>). ±1 까지는 예전 게인 그대로, 그 너머는 로그 연장입니다.
    /// </summary>
    public const double MaximumWhiteBalance = 4.0;

    /// <summary>
    /// 온도·틴트 손잡이의 거듭제곱 지수 — 예전 끝값(±1)이 손잡이 40% 지점에 오도록 정합니다.
    /// </summary>
    public static double WhiteBalancePositionExponent { get; } =
        Math.Log(1.0 / MaximumWhiteBalance) / Math.Log(0.4);

    internal bool IsValid() =>
        new[] { Warmth, Tint }.All(value =>
            double.IsFinite(value) && Math.Abs(value) <= MaximumWhiteBalance) &&
        new[]
        {
            ColorDepth, Vibrance, Saturation,
            RedPrimary, GreenPrimary, BluePrimary,
        }.All(value => double.IsFinite(value) && value is >= -1.0 and <= 1.0);
}
