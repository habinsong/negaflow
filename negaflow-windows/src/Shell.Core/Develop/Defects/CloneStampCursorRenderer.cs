using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 복제 도장 커서입니다. macOS
/// <c>Features/Defects/CloneStamp/CloneStampOverlay.swift</c> 의 <c>draw</c> 를 그대로 옮긴
/// 것입니다 — 브러시 원, Alt 를 누르고 있을 때의 십자선, 그리고 소스 십자선.
/// </summary>
/// <remarks>
/// macOS 는 원 안에 복제될 소스 화소를 미리 보여 줍니다. 그것은 표시 이미지 자체를 오프셋만큼
/// 옮겨 원으로 잘라 그리는 것이므로 캔버스 합성 단계의 일이고, 여기서는 macOS 와 같은 굵기·색의
/// 테두리와 십자선만 냅니다.
/// </remarks>
public static class CloneStampCursorRenderer
{
    /// <summary>macOS <c>drawCrosshair</c> 의 팔 길이입니다.</summary>
    private const int CrosshairArm = 7;

    /// <summary>macOS 원 테두리: 검정 0.55 를 2.5 로, 그 위에 흰색 0.9 를 1 로.</summary>
    private static readonly DefectOverlayColor RingShadow = new(0, 0, 0, 0.55);

    private static readonly DefectOverlayColor RingHighlight = new(255, 255, 255, 0.9);

    /// <summary>macOS 십자선: 검정 0.65 를 3 으로, 그 위에 흰색 0.95 를 1.2 로.</summary>
    private static readonly DefectOverlayColor CrosshairShadow = new(0, 0, 0, 0.65);

    private static readonly DefectOverlayColor CrosshairHighlight = new(255, 255, 255, 0.95);

    private const double RingShadowThickness = 2.5;

    private const double RingHighlightThickness = 1.0;

    private const double CrosshairShadowThickness = 3.0;

    private const double CrosshairHighlightThickness = 1.2;

    /// <summary>
    /// macOS <c>screenDiameter</c>: <c>max(3, sizePx × pxToScreenScale)</c>. 표시 화소 크기
    /// 기준이라 줌·크롭과 정합합니다.
    /// </summary>
    public static double ScreenDiameter(
        double diameterPixels,
        int displayWidth,
        uint sourceWidth) =>
        Math.Max(
            3.0,
            diameterPixels * (displayWidth / (double)Math.Max(1U, sourceWidth)));

    /// <summary>
    /// 표시 크기 <paramref name="width"/>×<paramref name="height"/> 의 BGRA8 커서입니다.
    /// 그릴 것이 없으면 <see langword="null"/> 입니다.
    /// </summary>
    /// <param name="cursor">커서(또는 진행 중 획의 마지막 점)의 표시 정규 좌표.</param>
    /// <param name="source">지정된 복제 소스의 표시 정규 좌표. 없으면 <see langword="null"/>.</param>
    /// <param name="optionDown">
    /// Alt 를 누르고 있는지. macOS 는 이때 브러시 원 대신 십자선만 냅니다.
    /// </param>
    public static byte[]? Render(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        DefectPoint? cursor,
        DefectPoint? source,
        double screenDiameter,
        bool optionDown)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (width <= 0 || height <= 0 ||
            (cursor is null && source is null) ||
            DefectDisplayLocator.Build(frame, width, height) is not { } locator)
        {
            return null;
        }

        byte[] bgra = new byte[checked(width * height * 4)];
        DefectCanvas canvas = new(bgra, width, height);

        // macOS: `if optionDown { source 와 cursor 에 십자선만; return }`
        if (optionDown)
        {
            DrawCrosshair(canvas, locator, source);
            DrawCrosshair(canvas, locator, cursor);
            return canvas.Touched ? bgra : null;
        }

        if (cursor is { } point && locator.TryLocate(point, out int x, out int y))
        {
            DrawRing(canvas, x, y, screenDiameter);
        }
        // macOS: 획 중에는 커서를 따라가고, 그 외에는 지정된 소스에 십자선을 냅니다.
        DrawCrosshair(canvas, locator, source);
        return canvas.Touched ? bgra : null;
    }

    private static void DrawRing(
        DefectCanvas canvas,
        int centerX,
        int centerY,
        double diameter)
    {
        double radius = diameter / 2.0;
        StrokeCircle(canvas, centerX, centerY, radius, RingShadowThickness, RingShadow);
        StrokeCircle(canvas, centerX, centerY, radius, RingHighlightThickness, RingHighlight);
    }

    /// <summary>
    /// 반지름 <paramref name="radius"/> 의 원 테두리를 <paramref name="thickness"/> 굵기로
    /// 칠합니다 — macOS <c>ctx.stroke(Path(ellipseIn:), lineWidth:)</c> 와 같은 그림입니다.
    /// </summary>
    private static void StrokeCircle(
        DefectCanvas canvas,
        int centerX,
        int centerY,
        double radius,
        double thickness,
        DefectOverlayColor color)
    {
        double half = thickness / 2.0;
        double outer = radius + half;
        double inner = Math.Max(0.0, radius - half);
        int extent = (int)Math.Ceiling(outer);
        double outerSquared = outer * outer;
        double innerSquared = inner * inner;
        for (int dy = -extent; dy <= extent; ++dy)
        {
            for (int dx = -extent; dx <= extent; ++dx)
            {
                double distance = (dx * dx) + (dy * dy);
                if (distance <= outerSquared && distance >= innerSquared)
                {
                    canvas.FillRectangle(centerX + dx, centerY + dy, 1, 1, color);
                }
            }
        }
    }

    /// <summary>macOS <c>drawCrosshair</c>: 팔 7, 검정 3 위에 흰색 1.2.</summary>
    private static void DrawCrosshair(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        DefectPoint? point)
    {
        if (point is not { } value || !locator.TryLocate(value, out int x, out int y))
        {
            return;
        }
        Cross(canvas, x, y, CrosshairShadowThickness, CrosshairShadow);
        Cross(canvas, x, y, CrosshairHighlightThickness, CrosshairHighlight);
    }

    private static void Cross(
        DefectCanvas canvas,
        int x,
        int y,
        double thickness,
        DefectOverlayColor color)
    {
        double half = thickness / 2.0;
        canvas.FillRectangle(
            x - CrosshairArm,
            (int)Math.Round(y - half),
            (CrosshairArm * 2) + 1,
            thickness,
            color);
        canvas.FillRectangle(
            (int)Math.Round(x - half),
            y - CrosshairArm,
            thickness,
            (CrosshairArm * 2) + 1,
            color);
    }
}
