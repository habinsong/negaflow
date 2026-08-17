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

    public bool Contains(double x, double y) =>
        x >= Left && x <= Right && y >= Top && y <= Bottom;

    public bool TryMapPoint(double x, double y, out CropDisplayPoint point)
    {
        if (!Contains(x, y) || Width <= 0.0 || Height <= 0.0)
        {
            point = default;
            return false;
        }

        point = new CropDisplayPoint((x - Left) / Width, (y - Top) / Height).Clamp();
        return true;
    }
}
