using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 복제 도장 커서입니다. macOS
/// <c>Features/Defects/CloneStamp/CloneStampOverlay.swift</c> 의 <c>draw</c> 를 그대로 옮긴
/// 것입니다 — Alt 를 누르고 있을 때의 십자선, 진행 중 획의 소스 창 미리보기, 브러시 원과 그 안의
/// 소스 화소 미리보기, 그리고 샘플 위치 십자선입니다.
/// </summary>
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
    /// <param name="reference">
    /// macOS <c>referenceImage</c> — 화면에 보이는 미리보기 화소(BGRA8, 덮개와 같은 격자)입니다.
    /// 없으면 미리보기 없이 테두리와 십자선만 냅니다.
    /// </param>
    /// <param name="cursor">macOS <c>current.last ?? hoverPoint</c> 의 표시 정규 좌표.</param>
    /// <param name="stroke">macOS <c>current</c> — 진행 중인 획의 표시 정규 좌표.</param>
    /// <param name="source">macOS <c>sourceBase</c> — 지정된 복제 소스. 없으면 <see langword="null"/>.</param>
    /// <param name="alignedRawOffset">macOS <c>alignedOffsetBase</c>.</param>
    /// <param name="optionDown">
    /// macOS <c>optionDown</c>. 이때는 브러시 원 대신 십자선만 냅니다.
    /// </param>
    public static byte[]? Render(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        byte[]? reference,
        DefectPoint? cursor,
        IReadOnlyList<DefectPoint> stroke,
        DefectPoint? source,
        DefectPoint? alignedRawOffset,
        double screenDiameter,
        bool optionDown)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(stroke);
        if (width <= 0 || height <= 0 ||
            (cursor is null && source is null && stroke.Count == 0))
        {
            return null;
        }

        byte[] bgra = new byte[checked(width * height * 4)];
        DefectCanvas canvas = new(bgra, width, height);
        double diameter = screenDiameter;

        // macOS: `if optionDown { source 와 cursor 에 십자선만; return }`
        if (optionDown)
        {
            DrawCrosshair(canvas, source, width, height);
            DrawCrosshair(canvas, cursor, width, height);
            return canvas.Touched ? bgra : null;
        }

        // macOS: `let anchor = current.first ?? cursor`,
        //        `let offset = anchor.flatMap { displayOffset(forCursorAt: $0) }`
        DefectPoint? anchor = stroke.Count > 0 ? stroke[0] : cursor;
        (int X, int Y)? offset = source is { } sourceAnchor && anchor is { } anchorPoint
            ? CloneStampSourceWindow.TryOffset(
                frame, width, height, anchorPoint, sourceAnchor, alignedRawOffset)
            : null;
        CloneStampSourceWindow? window = offset is { } shift
            ? CloneStampSourceWindow.TryCreate(reference, width, height, shift.X, shift.Y)
            : null;

        // macOS: 진행 중 스트로크는 소스 창의 실제 픽셀을 스트로크 모양으로 보여 줍니다.
        if (stroke.Count > 0 && window is not null)
        {
            Fill(
                canvas,
                CloneStampShapeMask.ForStroke(
                    Pixels(stroke, width, height), diameter / 2.0, width, height),
                window);
        }

        // macOS: `if let p = cursor, imageFrame.insetBy(dx: -diameter, dy: -diameter).contains(p)`
        if (cursor is { } point)
        {
            (int x, int y) = CloneStampSourceWindow.Pixel(point.X, point.Y, width, height);
            if (WithinExpandedImage(x, y, diameter, width, height))
            {
                // macOS: 원 안에 복제될 소스 픽셀 미리보기(소스 지정 후).
                if (source is not null && window is not null)
                {
                    Fill(
                        canvas,
                        CloneStampShapeMask.ForDisc(x, y, diameter / 2.0, width, height),
                        window);
                }
                DrawRing(canvas, x, y, diameter);
            }
        }

        // macOS: 샘플 위치 십자 — 획 중에는 커서를 따라가고, 그 외에는 지정된 소스에 냅니다.
        if (stroke.Count > 0 && offset is { } sample)
        {
            (int lastX, int lastY) = CloneStampSourceWindow.Pixel(
                stroke[^1].X, stroke[^1].Y, width, height);
            DrawCrosshair(canvas, lastX + sample.X, lastY + sample.Y);
        }
        else if (source is { } marker)
        {
            DrawCrosshair(canvas, marker, width, height);
        }
        return canvas.Touched ? bgra : null;
    }

    private static List<(int X, int Y)> Pixels(
        IReadOnlyList<DefectPoint> points,
        int width,
        int height)
    {
        List<(int X, int Y)> located = new(points.Count);
        foreach (DefectPoint point in points)
        {
            located.Add(CloneStampSourceWindow.Pixel(point.X, point.Y, width, height));
        }
        return located;
    }

    /// <summary>잘라 낸 모양 안을 소스 화소로 채웁니다 — macOS 는 여기서 이미지를 한 번 그립니다.</summary>
    private static void Fill(
        DefectCanvas canvas,
        CloneStampShapeMask? shape,
        CloneStampSourceWindow window)
    {
        if (shape is null)
        {
            return;
        }
        for (int y = shape.Top; y <= shape.Bottom; ++y)
        {
            for (int x = shape.Left; x <= shape.Right; ++x)
            {
                if (shape.Contains(x, y))
                {
                    window.CopyInto(canvas, x, y);
                }
            }
        }
    }

    /// <summary>
    /// macOS <c>imageFrame.insetBy(dx: -diameter, dy: -diameter).contains(p)</c> — 사진 밖으로
    /// 지름만큼 나가도 원은 그립니다.
    /// </summary>
    private static bool WithinExpandedImage(
        int x,
        int y,
        double diameter,
        int width,
        int height) =>
        x >= -diameter && x <= (width - 1) + diameter &&
        y >= -diameter && y <= (height - 1) + diameter;

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
                    canvas.BlendOver(centerX + dx, centerY + dy, color);
                }
            }
        }
    }

    private static void DrawCrosshair(
        DefectCanvas canvas,
        DefectPoint? point,
        int width,
        int height)
    {
        if (point is not { } value)
        {
            return;
        }
        (int x, int y) = CloneStampSourceWindow.Pixel(value.X, value.Y, width, height);
        DrawCrosshair(canvas, x, y);
    }

    /// <summary>macOS <c>drawCrosshair</c>: 팔 7, 검정 3 위에 흰색 1.2.</summary>
    private static void DrawCrosshair(DefectCanvas canvas, int x, int y)
    {
        Cross(canvas, x, y, CrosshairShadowThickness, CrosshairShadow);
        Cross(canvas, x, y, CrosshairHighlightThickness, CrosshairHighlight);
    }

    /// <summary>
    /// 가로 팔과 세로 팔을 한 번에 냅니다. macOS 는 하위 경로 둘을 담은 <c>Path</c> 하나를 한 번
    /// 긋기 때문에 교차하는 가운데도 <b>한 번만</b> 칠해집니다 — 두 번 얹으면 가운데가 진해집니다.
    /// </summary>
    private static void Cross(
        DefectCanvas canvas,
        int x,
        int y,
        double thickness,
        DefectOverlayColor color)
    {
        double half = thickness / 2.0;
        int horizontalTop = (int)Math.Round(y - half);
        int horizontalBottom = (int)Math.Ceiling(horizontalTop + thickness) - 1;
        int verticalLeft = (int)Math.Round(x - half);
        int verticalRight = (int)Math.Ceiling(verticalLeft + thickness) - 1;
        for (int row = y - CrosshairArm; row <= y + CrosshairArm; ++row)
        {
            for (int column = x - CrosshairArm; column <= x + CrosshairArm; ++column)
            {
                bool horizontal = row >= horizontalTop && row <= horizontalBottom;
                bool vertical = column >= verticalLeft && column <= verticalRight;
                if (horizontal || vertical)
                {
                    canvas.BlendOver(column, row, color);
                }
            }
        }
    }
}
