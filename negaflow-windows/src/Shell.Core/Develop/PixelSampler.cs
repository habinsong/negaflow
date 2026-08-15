namespace Negaflow.Shell.Develop;

/// <summary>원본 화소 자리입니다. 화면 좌표가 아니라 사진 좌표입니다.</summary>
public readonly record struct PixelCoordinate(int X, int Y);

/// <summary>한 화소의 값입니다. 0…255 로 읽습니다 — macOS 도 같은 눈금으로 보여 줍니다.</summary>
public readonly record struct PixelColorReading(int Red, int Green, int Blue)
{
    /// <summary>
    /// CIE Lab 입니다. sRGB 를 D65 로 놓고 계산합니다 — macOS 가 화면에 적는 것과 같은 값이며,
    /// 색을 눈이 아니라 수로 견줄 때 RGB 보다 쓸모가 있습니다.
    /// </summary>
    public (double L, double A, double B) Lab
    {
        get
        {
            (double x, double y, double z) = ToXyz();
            // D65 백색점입니다.
            double fx = LabF(x / 0.95047);
            double fy = LabF(y / 1.0);
            double fz = LabF(z / 1.08883);
            return ((116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz));
        }
    }

    private (double X, double Y, double Z) ToXyz()
    {
        double r = Linear(Red / 255.0);
        double g = Linear(Green / 255.0);
        double b = Linear(Blue / 255.0);
        return (
            (0.4124564 * r) + (0.3575761 * g) + (0.1804375 * b),
            (0.2126729 * r) + (0.7151522 * g) + (0.0721750 * b),
            (0.0193339 * r) + (0.1191920 * g) + (0.9503041 * b));
    }

    private static double Linear(double channel) =>
        channel <= 0.04045 ? channel / 12.92 : Math.Pow((channel + 0.055) / 1.055, 2.4);

    private static double LabF(double value) =>
        value > 0.008856 ? Math.Cbrt(value) : ((903.3 * value) + 16) / 116;
}

/// <summary>
/// 포인터 아래 화소의 값입니다.
/// </summary>
/// <remarks>
/// macOS 는 원본·작업·프루프 셋을 나란히 보여 줍니다. 여기서는 <b>원본</b>과 <b>화면에 보이는
/// 것</b> 둘입니다 — Windows 미리보기는 한 번에 버퍼 하나만 만들고, 프루프를 켜면 그 버퍼가 곧
/// 프루프 결과입니다. 작업본을 함께 보이려면 미리보기를 한 번 더 돌려야 하는데, 슬라이더를
/// 움직이는 동안 렌더가 두 배가 됩니다. 그래서 보이는 줄에는 지금 무엇을 보고 있는지를
/// 이름으로 밝힙니다.
/// </remarks>
public sealed record PixelSamplerReadout(
    PixelCoordinate SourceCoordinate,
    PixelColorReading? Original,
    PixelColorReading? Displayed,
    bool DisplayedIsProof);

public static class PixelSampler
{
    /// <summary>
    /// BGRA8 버퍼에서 한 화소를 읽습니다. 자리가 버퍼 밖이면 null 입니다 — 없는 화소의 값을
    /// 지어내지 않습니다.
    /// </summary>
    public static PixelColorReading? Read(
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        int x,
        int y)
    {
        if (width <= 0 || height <= 0 || x < 0 || y < 0 || x >= width || y >= height)
        {
            return null;
        }
        int at = ((y * width) + x) * 4;
        return at + 2 < bgra.Length
            ? new PixelColorReading(bgra[at + 2], bgra[at + 1], bgra[at])
            : null;
    }

    /// <summary>
    /// 화면 좌표를 사진 좌표로 옮깁니다. 사진은 캔버스 안에 비율을 지키며 가운데 놓이므로,
    /// 그 배율과 여백을 되돌립니다.
    /// </summary>
    public static PixelCoordinate? ToSourceCoordinate(
        double pointerX,
        double pointerY,
        double canvasWidth,
        double canvasHeight,
        int imageWidth,
        int imageHeight)
    {
        if (canvasWidth <= 0 || canvasHeight <= 0 || imageWidth <= 0 || imageHeight <= 0)
        {
            return null;
        }
        double scale = Math.Min(canvasWidth / imageWidth, canvasHeight / imageHeight);
        double drawnWidth = imageWidth * scale;
        double drawnHeight = imageHeight * scale;
        double left = (canvasWidth - drawnWidth) / 2;
        double top = (canvasHeight - drawnHeight) / 2;
        double x = (pointerX - left) / scale;
        double y = (pointerY - top) / scale;
        // 사진 밖이면 읽을 화소가 없습니다.
        return x < 0 || y < 0 || x >= imageWidth || y >= imageHeight
            ? null
            : new PixelCoordinate((int)x, (int)y);
    }
}
