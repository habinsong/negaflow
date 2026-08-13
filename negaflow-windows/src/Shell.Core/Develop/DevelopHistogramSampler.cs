namespace Negaflow.Shell;

public sealed record DevelopHistogramBins(
    int[] Luma,
    int[] Red,
    int[] Green,
    int[] Blue,
    int TotalPixels,
    int ShadowRed,
    int ShadowGreen,
    int ShadowBlue,
    int HighlightRed,
    int HighlightGreen,
    int HighlightBlue)
{
    /// <summary>
    /// 클리핑으로 볼 최소 화소 수입니다. macOS <c>HistogramBins.isClipped</c> 와 같이 표본의
    /// 0.2% 이며 최소 1입니다 — 한두 화소가 끝에 닿았다고 경고를 띄우지 않기 위한 값입니다.
    /// </summary>
    public int ClippingThreshold => Math.Max((int)(TotalPixels * 0.002), 1);

    /// <summary>
    /// 어두운 쪽이든 밝은 쪽이든 문턱을 넘은 채널의 이름입니다. macOS 와 같은 R/G/B 순서이며,
    /// 걸린 것이 없으면 빈 목록입니다.
    /// </summary>
    public IReadOnlyList<string> ClippedChannels
    {
        get
        {
            int threshold = ClippingThreshold;
            List<string> clipped = [];
            if (ShadowRed > threshold || HighlightRed > threshold)
            {
                clipped.Add("R");
            }
            if (ShadowGreen > threshold || HighlightGreen > threshold)
            {
                clipped.Add("G");
            }
            if (ShadowBlue > threshold || HighlightBlue > threshold)
            {
                clipped.Add("B");
            }
            return clipped;
        }
    }
}

public static class DevelopHistogramSampler
{
    public const int BinCount = 64;

    public const int MaximumSampleCount = 256 * 1024;

    public static DevelopHistogramBins? SampleBgra8(byte[] pixels, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(pixels);
        if (width <= 0 || height <= 0)
        {
            return null;
        }

        long pixelCountLong = (long)width * height;
        long requiredBytes = pixelCountLong * 4;
        if (pixelCountLong > int.MaxValue || requiredBytes > pixels.Length)
        {
            return null;
        }

        int pixelCount = (int)pixelCountLong;
        int step = Math.Max(1, (pixelCount + MaximumSampleCount - 1) / MaximumSampleCount);
        int[] luma = new int[BinCount];
        int[] red = new int[BinCount];
        int[] green = new int[BinCount];
        int[] blue = new int[BinCount];
        int shadowRed = 0;
        int shadowGreen = 0;
        int shadowBlue = 0;
        int highlightRed = 0;
        int highlightGreen = 0;
        int highlightBlue = 0;
        int total = 0;

        for (int pixel = 0; pixel < pixelCount; pixel += step)
        {
            int offset = pixel * 4;
            byte b = pixels[offset];
            byte g = pixels[offset + 1];
            byte r = pixels[offset + 2];
            byte a = pixels[offset + 3];
            if (a == 0)
            {
                continue;
            }

            int luminance = (int)Math.Round((0.2126 * r) + (0.7152 * g) + (0.0722 * b));
            luma[Math.Min(BinCount - 1, luminance * BinCount / 256)]++;
            red[r * BinCount / 256]++;
            green[g * BinCount / 256]++;
            blue[b * BinCount / 256]++;
            total++;

            if (r == 0) shadowRed++;
            if (g == 0) shadowGreen++;
            if (b == 0) shadowBlue++;
            if (r == byte.MaxValue) highlightRed++;
            if (g == byte.MaxValue) highlightGreen++;
            if (b == byte.MaxValue) highlightBlue++;
        }

        return new DevelopHistogramBins(
            luma,
            red,
            green,
            blue,
            total,
            shadowRed,
            shadowGreen,
            shadowBlue,
            highlightRed,
            highlightGreen,
            highlightBlue);
    }
}
