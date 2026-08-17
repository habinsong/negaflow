using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 고른 레이어 하나의 검출 위치를 캔버스 위에 그립니다. macOS
/// <c>Features/Defects/DefectMaskOverlay.swift</c> 를 그대로 옮긴 것입니다 — region 은 저장된
/// 미리보기 점을 분류색으로, 브러시와 복제 도장은 획 경로를 주황으로, 복제는 소스 십자까지.
/// </summary>
public static class DefectMaskOverlayRenderer
{
    /// <summary>macOS 가 미리보기 점 하나에 채우는 사각형의 한 변입니다(3pt).</summary>
    private const int PreviewPointSize = 3;

    /// <summary>macOS 소스 십자의 팔 길이(6pt)와 굵기(1.5pt)입니다.</summary>
    private const int CrossArm = 6;

    private const double CrossThickness = 1.5;

    /// <summary>macOS <c>.orange.opacity(0.4)</c>.</summary>
    private const double StrokeAlpha = 0.4;

    /// <summary>macOS <c>.orange.opacity(0.8)</c>.</summary>
    private const double CrossAlpha = 0.8;

    /// <summary>
    /// 표시 크기 <paramref name="width"/>×<paramref name="height"/> 의 BGRA8 덮개입니다.
    /// 그릴 것이 없으면 <see langword="null"/> 입니다.
    /// </summary>
    public static byte[]? Render(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        DefectEditItem item)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(item);
        if (DefectDisplayLocator.Build(frame, width, height) is not { } locator)
        {
            return null;
        }

        byte[] bgra = new byte[checked(width * height * 4)];
        DefectCanvas canvas = new(bgra, width, height);
        switch (item.Kind)
        {
            case DefectEditKind.Brush:
                DrawBrush(canvas, locator, item);
                break;
            case DefectEditKind.Clone:
                DrawClone(canvas, locator, item, frame);
                break;
            default:
                DrawRegion(canvas, locator, item);
                break;
        }
        return canvas.Touched ? bgra : null;
    }

    /// <summary>
    /// macOS <c>drawRegion</c>: 미리보기 점마다 분류색 3×3 사각형. 확신이 불투명도가 됩니다.
    /// </summary>
    private static void DrawRegion(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        DefectEditItem item)
    {
        foreach (DefectPreviewComponent component in item.Preview)
        {
            DefectOverlayColor color = DefectClassPalette.ForComponent(
                component.Classification,
                component.Confidence);
            foreach (DefectPoint point in component.Points)
            {
                if (locator.TryLocate(point, out int x, out int y))
                {
                    canvas.FillSquare(x, y, PreviewPointSize, color);
                }
            }
        }
    }

    /// <summary>
    /// macOS <c>drawBrush</c>: 굵기는 짧은 변에 대한 비율이므로 표시 크기의 짧은 변을 곱합니다.
    /// </summary>
    private static void DrawBrush(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        DefectEditItem item)
    {
        if (item.Strokes is not { } strokes)
        {
            return;
        }
        double shortSide = Math.Min(canvas.Width, canvas.Height);
        DefectOverlayColor color = DefectClassPalette.Orange with { Alpha = StrokeAlpha };
        foreach (DefectStroke stroke in strokes)
        {
            double lineWidth = Math.Max(1.0, stroke.Thickness * shortSide);
            DrawPath(canvas, locator, stroke.Points, lineWidth, color);
        }
    }

    /// <summary>
    /// macOS <c>drawClone</c>: 지름은 원본 화소 단위라 표시 배율을 곱합니다. 소스 위치는 첫 점에
    /// 변위를 더한 자리에 십자로 냅니다.
    /// </summary>
    private static void DrawClone(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        DefectEditItem item,
        LibraryFrameSnapshot frame)
    {
        if (item.CloneStrokes is not { } strokes)
        {
            return;
        }
        double scale = PixelToScreenScale(canvas, frame, item.BaseSize);
        DefectOverlayColor path = DefectClassPalette.Orange with { Alpha = StrokeAlpha };
        DefectOverlayColor cross = DefectClassPalette.Orange with { Alpha = CrossAlpha };
        foreach (DefectCloneStroke stroke in strokes)
        {
            DrawPath(
                canvas,
                locator,
                stroke.Points,
                Math.Max(1.0, stroke.Diameter * scale),
                path);
            if (stroke.Points.Count == 0)
            {
                continue;
            }
            DefectPoint first = stroke.Points[0];
            DefectPoint source = new(first.X + stroke.OffsetX, first.Y + stroke.OffsetY);
            if (locator.TryLocate(source, out int x, out int y))
            {
                canvas.FillRectangle(x - CrossArm, y, (CrossArm * 2) + 1, CrossThickness, cross);
                canvas.FillRectangle(x, y - CrossArm, CrossThickness, (CrossArm * 2) + 1, cross);
            }
        }
    }

    /// <summary>
    /// 원본 화소 하나가 화면에서 차지하는 크기입니다. macOS <c>pixelToScreenScale</c> 과 같이
    /// 회전이 폭과 높이를 바꾸는 것까지 셉니다.
    /// </summary>
    private static double PixelToScreenScale(
        DefectCanvas canvas,
        LibraryFrameSnapshot frame,
        DefectSize? baseSize)
    {
        double width = baseSize?.Width ?? frame.SourceMetadata?.PixelWidth ?? 0.0;
        double height = baseSize?.Height ?? frame.SourceMetadata?.PixelHeight ?? 0.0;
        if (width <= 0.0 || height <= 0.0)
        {
            return 1.0;
        }
        bool swaps = frame.ImageTransform.Rotation is
            ImageRotation.Degrees90 or ImageRotation.Degrees270;
        return canvas.Width / Math.Max(swaps ? height : width, 1.0);
    }

    /// <summary>
    /// 점 하나면 원, 여럿이면 이은 선입니다. 선은 표시 공간에서 굵기만큼의 원을 따라 찍어
    /// 그립니다 — macOS 의 <c>lineCap: .round</c> 와 같은 모양입니다.
    /// </summary>
    private static void DrawPath(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        IReadOnlyList<DefectPoint> points,
        double lineWidth,
        DefectOverlayColor color)
    {
        double radius = lineWidth / 2.0;
        List<(int X, int Y)> located = [];
        foreach (DefectPoint point in points)
        {
            if (locator.TryLocate(point, out int x, out int y))
            {
                located.Add((x, y));
            }
        }
        if (located.Count == 0)
        {
            return;
        }
        if (located.Count == 1)
        {
            canvas.FillCircle(located[0].X, located[0].Y, radius, color);
            return;
        }
        for (int index = 1; index < located.Count; ++index)
        {
            Stamp(canvas, located[index - 1], located[index], radius, color);
        }
    }

    private static void Stamp(
        DefectCanvas canvas,
        (int X, int Y) from,
        (int X, int Y) to,
        double radius,
        DefectOverlayColor color)
    {
        int steps = Math.Max(Math.Abs(to.X - from.X), Math.Abs(to.Y - from.Y));
        if (steps == 0)
        {
            canvas.FillCircle(from.X, from.Y, radius, color);
            return;
        }
        for (int step = 0; step <= steps; ++step)
        {
            double t = (double)step / steps;
            canvas.FillCircle(
                (int)Math.Round(from.X + ((to.X - from.X) * t)),
                (int)Math.Round(from.Y + ((to.Y - from.Y) * t)),
                radius,
                color);
        }
    }
}
