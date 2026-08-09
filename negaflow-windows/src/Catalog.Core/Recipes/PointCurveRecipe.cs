namespace Negaflow.Catalog;

/// <summary>
/// macOS <c>CurvePoint</c>와 같은 정규화된 입력/출력 점입니다.
/// </summary>
public readonly record struct PointCurvePoint(double X, double Y);

/// <summary>
/// macOS <c>PointCurves</c>의 RGB/Red/Green/Blue recipe입니다. 빈 채널은 identity curve를 뜻합니다.
/// </summary>
public sealed record PointCurveRecipe(
    IReadOnlyList<PointCurvePoint> Rgb,
    IReadOnlyList<PointCurvePoint> Red,
    IReadOnlyList<PointCurvePoint> Green,
    IReadOnlyList<PointCurvePoint> Blue)
{
    public const int MaximumPointsPerChannel = 64;

    public static PointCurveRecipe Identity { get; } = new([], [], [], []);
}
