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
