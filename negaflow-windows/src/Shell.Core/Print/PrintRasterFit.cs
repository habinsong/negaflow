namespace Negaflow.Shell.Print;

/// <summary>
/// XAML 이 그린 BGRA(premultiplied) 그림을 판에 찍을 화소 크기로 맞춥니다.
/// </summary>
/// <remarks>
/// <c>RenderTargetBitmap</c> 은 요소를 그 창의 화면 배율(<c>XamlRoot.RasterizationScale</c>)로 그립니다. 판에
/// 찍는 쪽은 요소를 그 배율로 나눈 크기로 놓아 판 화소 그대로 받지만, 배치 반올림으로 1px 어긋나거나 아주 큰
/// 띠가 DirectX 텍스처 한계에 걸려 줄어 나올 수 있습니다. 어느 경우든 판에는 배치 계산이 정한 크기 그대로
/// 찍혀야 화면 미리보기와 같습니다 — 받은 크기 그대로 붙이면 150% 화면에서 글자가 1.5배로 커져 띠 밖으로
/// 나갔습니다(사용자 신고).
/// </remarks>
public static class PrintRasterFit
{
    /// <summary>
    /// <paramref name="targetWidth"/> × <paramref name="targetHeight"/> 크기의 BGRA 를 돌려줍니다. 크기가 같으면
    /// 받은 배열을 그대로, 1px 안쪽으로 어긋나면 왼쪽 위를 맞춰 자르거나 투명으로 채우고, 그보다 다르면 넓이
    /// 평균으로 다시 표본을 뽑습니다.
    /// </summary>
    public static byte[] ToSize(byte[] bgra, int width, int height, int targetWidth, int targetHeight)
    {
        ArgumentNullException.ThrowIfNull(bgra);
        if (width < 1 || height < 1 || targetWidth < 1 || targetHeight < 1 ||
            bgra.Length < (long)width * height * 4)
        {
            throw new ArgumentException("BGRA size does not match its dimensions.", nameof(bgra));
        }
        if (width == targetWidth && height == targetHeight)
        {
            return bgra;
        }
        if (Math.Abs(width - targetWidth) <= 1 && Math.Abs(height - targetHeight) <= 1)
        {
            return Crop(bgra, width, height, targetWidth, targetHeight);
        }
        return Resample(bgra, width, height, targetWidth, targetHeight);
    }

    private static byte[] Crop(byte[] bgra, int width, int height, int targetWidth, int targetHeight)
    {
        byte[] result = new byte[targetWidth * targetHeight * 4];
        int rowBytes = Math.Min(width, targetWidth) * 4;
        for (int y = 0; y < Math.Min(height, targetHeight); ++y)
        {
            Buffer.BlockCopy(bgra, y * width * 4, result, y * targetWidth * 4, rowBytes);
        }
        return result;
    }

    /// <summary>가로 → 세로 두 번에 나눠 각 칸이 덮는 원본 넓이만큼 섞습니다(premultiplied 라 그대로 평균합니다).</summary>
    private static byte[] Resample(byte[] bgra, int width, int height, int targetWidth, int targetHeight)
    {
        float[] rows = new float[targetWidth * height * 4];
        double stepX = (double)width / targetWidth;
        for (int x = 0; x < targetWidth; ++x)
        {
            double start = x * stepX;
            double end = start + stepX;
            for (int source = (int)start; source < Math.Min(width, (int)Math.Ceiling(end)); ++source)
            {
                float weight = (float)((Math.Min(end, source + 1) - Math.Max(start, source)) / stepX);
                if (weight <= 0)
                {
                    continue;
                }
                for (int y = 0; y < height; ++y)
                {
                    int from = ((y * width) + source) * 4;
                    int to = ((y * targetWidth) + x) * 4;
                    rows[to] += bgra[from] * weight;
                    rows[to + 1] += bgra[from + 1] * weight;
                    rows[to + 2] += bgra[from + 2] * weight;
                    rows[to + 3] += bgra[from + 3] * weight;
                }
            }
        }
        byte[] result = new byte[targetWidth * targetHeight * 4];
        double stepY = (double)height / targetHeight;
        Span<float> sum = stackalloc float[4];
        for (int y = 0; y < targetHeight; ++y)
        {
            double start = y * stepY;
            double end = start + stepY;
            for (int x = 0; x < targetWidth; ++x)
            {
                sum.Clear();
                for (int source = (int)start; source < Math.Min(height, (int)Math.Ceiling(end)); ++source)
                {
                    float weight = (float)((Math.Min(end, source + 1) - Math.Max(start, source)) / stepY);
                    int from = ((source * targetWidth) + x) * 4;
                    for (int channel = 0; channel < 4; ++channel)
                    {
                        sum[channel] += rows[from + channel] * weight;
                    }
                }
                int to = ((y * targetWidth) + x) * 4;
                for (int channel = 0; channel < 4; ++channel)
                {
                    result[to + channel] = (byte)Math.Clamp((int)MathF.Round(sum[channel]), 0, 255);
                }
            }
        }
        return result;
    }
}
