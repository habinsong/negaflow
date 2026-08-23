namespace Negaflow.Shell.Develop;

/// <summary>
/// 캔버스 안에서 미리보기가 차지하는 사각형입니다. 크롭, 가이드 선택, 픽셀 샘플러가
/// 같은 기하를 써야 표시 좌표가 어긋나지 않습니다.
/// </summary>
public readonly record struct PreviewFrame(double Left, double Top, double Width, double Height)
{
    public const double DefaultInset = 48.0;

    public double Right => Left + Width;

    public double Bottom => Top + Height;

    public static bool TryFrom(
        double canvasWidth,
        double canvasHeight,
        int pixelWidth,
        int pixelHeight,
        out PreviewFrame frame,
        double inset = DefaultInset)
    {
        frame = default;
        if (pixelWidth <= 0 || pixelHeight <= 0 || canvasWidth <= 0.0 || canvasHeight <= 0.0)
        {
            return false;
        }

        double availableWidth = Math.Max(1.0, canvasWidth - inset);
        double availableHeight = Math.Max(1.0, canvasHeight - inset);
        double scale = Math.Min(
            availableWidth / pixelWidth,
            availableHeight / pixelHeight);
        double width = pixelWidth * scale;
        double height = pixelHeight * scale;
        if (width <= 0.0 || height <= 0.0)
        {
            return false;
        }

        frame = new PreviewFrame(
            (canvasWidth - width) / 2.0,
            (canvasHeight - height) / 2.0,
            width,
            height);
        return true;
    }

    /// <summary>macOS <c>canvasFittedImageFrame</c> — 줌·팬이 붙은 표시 사각형.</summary>
    public static bool TryFromViewport(
        double canvasWidth,
        double canvasHeight,
        int pixelWidth,
        int pixelHeight,
        double scale,
        double offsetX,
        double offsetY,
        out PreviewFrame frame)
    {
        frame = default;
        if (pixelWidth <= 0 || pixelHeight <= 0 || canvasWidth <= 0.0 || canvasHeight <= 0.0)
        {
            return false;
        }

        (double left, double top, double width, double height) = CanvasViewportGeometry.FittedImageFrame(
            pixelWidth,
            pixelHeight,
            canvasWidth,
            canvasHeight,
            scale,
            offsetX,
            offsetY);
        if (width <= 0.0 || height <= 0.0)
        {
            return false;
        }

        frame = new PreviewFrame(left, top, width, height);
        return true;
    }

    public bool Contains(double x, double y) =>
        x >= Left && x <= Right && y >= Top && y <= Bottom;

    public bool TryMapPoint(double x, double y, out CropDisplayPoint point) =>
        TryMapPoint(x, y, 0.0, out point, out _);

    /// <summary>
    /// 캔버스 좌표를 그림 안 정규 좌표로 옮깁니다. <paramref name="margin"/> 만큼은 그림
    /// <b>밖</b>이어도 받아 가장자리로 붙입니다.
    /// </summary>
    /// <remarks>
    /// 크롭 핸들은 모서리를 <b>가운데</b>에 두고 그려지므로 그 절반이 그림 밖에 있습니다.
    /// 밖을 거부하면 그 절반이 죽어, 눈에 보이는 핸들을 눌러도 아무 일이 없습니다 —
    /// 실측: 왼쪽 위 모서리를 정확히 눌렀을 때 <c>mapped=False</c>, 안쪽 4 부터만 잡혔고
    /// 사용자는 "좀 더 안쪽을 눌러야 동작한다" 고 신고했습니다. macOS 는 핸들 뷰마다
    /// 자기 제스처가 붙어 있어 그려진 사각형 전체가 잡힙니다.
    /// </remarks>
    public bool TryMapPoint(
        double x,
        double y,
        double margin,
        out CropDisplayPoint point,
        out bool inside)
    {
        inside = false;
        if (Width <= 0.0 || Height <= 0.0)
        {
            point = default;
            return false;
        }
        inside = Contains(x, y);
        double slack = Math.Max(0.0, margin);
        if (!inside &&
            (x < Left - slack || x > Right + slack || y < Top - slack || y > Bottom + slack))
        {
            point = default;
            return false;
        }

        point = new CropDisplayPoint((x - Left) / Width, (y - Top) / Height).Clamp();
        return true;
    }
}
