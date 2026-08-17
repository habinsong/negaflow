namespace Negaflow.Shell.Develop;

/// <summary>
/// 덮개 한 장을 채우는 자리입니다. BGRA8 이며 알파를 미리 곱해 둡니다 — WinUI
/// <c>WriteableBitmap</c> 이 미리 곱한 값을 기대하고, 곱하지 않으면 가장자리에 흰 테가 섭니다.
/// </summary>
internal sealed class DefectCanvas(byte[] pixels, int width, int height)
{
    private readonly byte[] pixels = pixels;

    public int Width { get; } = width;

    public int Height { get; } = height;

    /// <summary>한 화소라도 칠했는지. 아무것도 없으면 덮개를 아예 띄우지 않습니다.</summary>
    public bool Touched { get; private set; }

    public void FillSquare(int centerX, int centerY, int size, DefectOverlayColor color)
    {
        int half = size / 2;
        FillRectangle(centerX - half, centerY - half, size, size, color);
    }

    public void FillRectangle(int left, int top, double width, double height, DefectOverlayColor color)
    {
        int right = (int)Math.Ceiling(left + width);
        int bottom = (int)Math.Ceiling(top + height);
        for (int y = Math.Max(0, top); y < Math.Min(Height, bottom); ++y)
        {
            for (int x = Math.Max(0, left); x < Math.Min(Width, right); ++x)
            {
                Blend(x, y, color);
            }
        }
    }

    public void FillCircle(int centerX, int centerY, double radius, DefectOverlayColor color)
    {
        if (radius < 0.5)
        {
            Blend(centerX, centerY, color);
            return;
        }
        int extent = (int)Math.Ceiling(radius);
        double squared = radius * radius;
        for (int dy = -extent; dy <= extent; ++dy)
        {
            for (int dx = -extent; dx <= extent; ++dx)
            {
                if ((dx * dx) + (dy * dy) <= squared)
                {
                    Blend(centerX + dx, centerY + dy, color);
                }
            }
        }
    }

    /// <summary>
    /// 불투명한 화소 하나입니다. macOS 복제 도장이 원 안에 소스 이미지를 <b>그대로</b> 그리는
    /// 자리이며, 그 위에 테두리가 얹힙니다.
    /// </summary>
    public void Write(int x, int y, byte blue, byte green, byte red)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height)
        {
            return;
        }
        int index = ((y * Width) + x) * 4;
        pixels[index] = blue;
        pixels[index + 1] = green;
        pixels[index + 2] = red;
        pixels[index + 3] = 255;
        Touched = true;
    }

    /// <summary>
    /// SwiftUI <c>GraphicsContext</c> 와 같은 source-over 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Blend"/> 의 "더 진한 쪽만" 규칙은 획을 원으로 촘촘히 찍는 브러시 경로 전용입니다.
    /// 복제 도장 커서는 불투명한 소스 미리보기를 먼저 깔고 그 위에 테두리(검정 0.55 → 흰 0.9)를
    /// 얹으므로 그 규칙을 쓰면 테두리가 통째로 사라집니다. macOS 는 두 자리 모두 source-over 입니다.
    /// <b>같은 획 안에서 한 화소를 두 번 부르지 마십시오</b> — macOS 는 하위 경로 여럿을 한 번에
    /// 그으므로 겹치는 자리도 한 번만 칠해집니다.
    /// </remarks>
    public void BlendOver(int x, int y, DefectOverlayColor color)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height)
        {
            return;
        }
        double alpha = Math.Clamp(color.Alpha, 0.0, 1.0);
        if (alpha <= 0.0)
        {
            return;
        }
        int index = ((y * Width) + x) * 4;
        double keep = 1.0 - alpha;
        pixels[index] = Over(color.Blue, alpha, pixels[index], keep);
        pixels[index + 1] = Over(color.Green, alpha, pixels[index + 1], keep);
        pixels[index + 2] = Over(color.Red, alpha, pixels[index + 2], keep);
        pixels[index + 3] = Over(255, alpha, pixels[index + 3], keep);
        Touched = true;
    }

    /// <summary>미리 곱한 source-over 한 채널입니다: <c>src×α + dst×(1−α)</c>.</summary>
    private static byte Over(byte source, double alpha, byte destination, double keep) =>
        (byte)Math.Clamp(
            Math.Round((source * alpha) + (destination * keep)),
            0.0,
            255.0);

    /// <summary>
    /// 같은 자리에 두 번 칠해도 진해지지 않게 더 진한 쪽만 남깁니다 — 획을 원으로 촘촘히 찍어
    /// 그리므로 겹치는 것이 정상이고, 겹칠 때마다 더하면 획 가운데가 불투명해집니다.
    /// </summary>
    private void Blend(int x, int y, DefectOverlayColor color)
    {
        if (x < 0 || y < 0 || x >= Width || y >= Height)
        {
            return;
        }
        double alpha = Math.Clamp(color.Alpha, 0.0, 1.0);
        int index = ((y * Width) + x) * 4;
        byte target = (byte)Math.Round(alpha * 255.0);
        if (pixels[index + 3] >= target)
        {
            return;
        }
        pixels[index] = (byte)Math.Round(color.Blue * alpha);
        pixels[index + 1] = (byte)Math.Round(color.Green * alpha);
        pixels[index + 2] = (byte)Math.Round(color.Red * alpha);
        pixels[index + 3] = target;
        Touched = true;
    }
}
