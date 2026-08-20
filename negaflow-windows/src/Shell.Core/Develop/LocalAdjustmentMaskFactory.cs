using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>LocalAdjustmentMaskFactory</c> 그대로입니다 — 캔버스에서 끈 점들을 마스크로
/// 바꿉니다.
/// </summary>
/// <remarks>
/// 점은 모두 <b>원본 기준 0...1 좌표</b>입니다. 화면 좌표를 그대로 넣으면 확대율에 따라
/// 마스크가 달라지므로, 부르는 쪽이 먼저 환산합니다.
/// </remarks>
public static class LocalAdjustmentMaskFactory
{
    /// <summary>만들 수 없으면 <see langword="null"/> 입니다 — macOS 도 그때 아무 것도 안 만듭니다.</summary>
    public static LocalDodgeBurnMask? Make(
        LocalDodgeBurnMaskKind kind,
        IReadOnlyList<LocalDodgeBurnPoint> points,
        double thickness,
        double feather,
        double imageWidth = 0.0,
        double imageHeight = 0.0)
    {
        ArgumentNullException.ThrowIfNull(points);
        double clampedFeather = Math.Clamp(feather, 0.0, 1.0);
        switch (kind)
        {
            case LocalDodgeBurnMaskKind.Brush:
                if (points.Count == 0)
                {
                    return null;
                }
                return LocalDodgeBurnMask.Brush([
                    new LocalDodgeBurnStroke(
                        [.. points],
                        Math.Clamp(
                            thickness,
                            LocalAdjustmentSession.MinimumBrushThickness,
                            LocalAdjustmentSession.MaximumBrushThickness),
                        clampedFeather * LocalAdjustmentEditing.BrushFeatherScale),
                ]);

            case LocalDodgeBurnMaskKind.Radial:
                if (points.Count < 2)
                {
                    return null;
                }
                return LocalDodgeBurnMask.Radial(
                    points[0],
                    Math.Max(0.005, RadialRadius(points[0], points[^1], imageWidth, imageHeight)),
                    clampedFeather);

            case LocalDodgeBurnMaskKind.Linear:
                if (points.Count < 2 || Distance(points[0], points[^1]) <= 0.001)
                {
                    return null;
                }
                return LocalDodgeBurnMask.Linear(points[0], points[^1], clampedFeather);

            case LocalDodgeBurnMaskKind.Polygon:
                return points.Count < 3
                    ? null
                    : LocalDodgeBurnMask.Polygon([.. points], clampedFeather);

            default:
                return null;
        }
    }

    /// <summary>
    /// macOS <c>radialRadius</c> — 원본 크기를 알면 짧은 변으로 나눠 <b>화면이 아니라 사진</b>
    /// 기준의 원을 만듭니다. 모르면 정규화 좌표 거리를 그대로 씁니다.
    /// </summary>
    private static double RadialRadius(
        LocalDodgeBurnPoint start,
        LocalDodgeBurnPoint end,
        double imageWidth,
        double imageHeight)
    {
        if (imageWidth <= 0.0 || imageHeight <= 0.0)
        {
            return Distance(start, end);
        }
        double minimum = Math.Min(imageWidth, imageHeight);
        double dx = (start.X - end.X) * imageWidth;
        double dy = (start.Y - end.Y) * imageHeight;
        return Math.Sqrt((dx * dx) + (dy * dy)) / minimum;
    }

    private static double Distance(LocalDodgeBurnPoint start, LocalDodgeBurnPoint end)
    {
        double dx = start.X - end.X;
        double dy = start.Y - end.Y;
        return Math.Sqrt((dx * dx) + (dy * dy));
    }
}
