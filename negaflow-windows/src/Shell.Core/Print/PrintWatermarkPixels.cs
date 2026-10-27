namespace Negaflow.Shell.Print;

/// <summary>
/// 워터마크의 히스토그램과 블러 바탕을 작은 그림(필름스트립 썸네일)에서 만듭니다. macOS
/// <c>PrintWatermarkHistogram</c> · 블러 바탕과 같은 크기·같은 식입니다. 미리보기와 판이 같은
/// 썸네일을 쓰므로 둘의 히스토그램은 같습니다.
/// </summary>
public static class PrintWatermarkPixels
{
    /// <summary>
    /// BGRA8(불투명) 화소의 표시 밝기 분포입니다. Rec. 709 가중치로 32 칸에 세고 가장 높은 칸을
    /// 1 로 맞춥니다. 반투명 화소는 셈에서 뺍니다.
    /// </summary>
    public static double[] HistogramColumns(
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        int count = PrintWatermarkMetrics.HistogramColumns)
    {
        double[] bins = new double[Math.Max(1, count)];
        if (width < 1 || height < 1 || bgra.Length < width * height * 4)
        {
            return bins;
        }
        for (int index = 0; index < width * height * 4; index += 4)
        {
            if (bgra[index + 3] != 255)
            {
                continue;
            }
            double luma = (0.2126 * bgra[index + 2]) + (0.7152 * bgra[index + 1]) + (0.0722 * bgra[index]);
            bins[Math.Min(bins.Length - 1, (int)(luma * bins.Length / 256))] += 1;
        }
        double peak = bins.Max();
        if (peak > 0)
        {
            for (int index = 0; index < bins.Length; ++index)
            {
                bins[index] /= peak;
            }
        }
        return bins;
    }

    /// <summary>긴 변을 <paramref name="maximumEdge"/> 이하로 상자 평균해 줄입니다(크기가 이미 작으면 그대로).</summary>
    public static (byte[] Pixels, int Width, int Height) Downscale(
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        int maximumEdge)
    {
        int longest = Math.Max(width, height);
        if (longest <= maximumEdge || width < 1 || height < 1)
        {
            return (bgra[..(width * height * 4)].ToArray(), width, height);
        }
        double scale = (double)maximumEdge / longest;
        int outWidth = Math.Max(1, (int)Math.Round(width * scale, MidpointRounding.AwayFromZero));
        int outHeight = Math.Max(1, (int)Math.Round(height * scale, MidpointRounding.AwayFromZero));
        byte[] result = new byte[outWidth * outHeight * 4];
        for (int y = 0; y < outHeight; ++y)
        {
            int y0 = y * height / outHeight;
            int y1 = Math.Max(y0 + 1, (y + 1) * height / outHeight);
            for (int x = 0; x < outWidth; ++x)
            {
                int x0 = x * width / outWidth;
                int x1 = Math.Max(x0 + 1, (x + 1) * width / outWidth);
                int b = 0, g = 0, r = 0, a = 0, n = 0;
                for (int sy = y0; sy < y1; ++sy)
                {
                    for (int sx = x0; sx < x1; ++sx)
                    {
                        int at = ((sy * width) + sx) * 4;
                        b += bgra[at];
                        g += bgra[at + 1];
                        r += bgra[at + 2];
                        a += bgra[at + 3];
                        ++n;
                    }
                }
                int to = ((y * outWidth) + x) * 4;
                result[to] = (byte)(b / n);
                result[to + 1] = (byte)(g / n);
                result[to + 2] = (byte)(r / n);
                result[to + 3] = (byte)(a / n);
            }
        }
        return (result, outWidth, outHeight);
    }

    /// <summary>
    /// 흐린 바탕 한 장입니다. 선형 빛으로 흐린 결과를 sRGB 부호화 값(0~1)으로 접어 담습니다 —
    /// 화소마다 거듭제곱을 다시 하지 않으려는 것이며, 흐린 면이라 보간 공간 차이는 보이지 않습니다.
    /// </summary>
    public sealed class BlurField
    {
        internal BlurField(float[] linearRgb, int width, int height)
        {
            Width = width;
            Height = height;
            Encoded = new float[linearRgb.Length];
            for (int index = 0; index < linearRgb.Length; ++index)
            {
                Encoded[index] = (float)Encode(linearRgb[index]);
            }
        }

        internal float[] Encoded { get; }

        public int Width { get; }

        public int Height { get; }

        /// <summary>화면에 걸 BGRA8 화소입니다.</summary>
        public byte[] EncodedBgra()
        {
            byte[] bgra = new byte[Width * Height * 4];
            for (int index = 0, from = 0; from < Encoded.Length; index += 4, from += 3)
            {
                bgra[index] = ToByte(Encoded[from + 2]);
                bgra[index + 1] = ToByte(Encoded[from + 1]);
                bgra[index + 2] = ToByte(Encoded[from]);
                bgra[index + 3] = 0xFF;
            }
            return bgra;
        }

        /// <summary>
        /// 띠 포함 한 장(<paramref name="frameWidth"/> × <paramref name="frameHeight"/>)을 가득 채우도록
        /// 늘렸을 때 (x, y) 자리의 색(sRGB 부호화 값 0~1)입니다. 가운데를 맞춰 남는 쪽을 잘라 냅니다
        /// (macOS 의 aspect fill 과 같습니다).
        /// </summary>
        public (double Red, double Green, double Blue) SampleFill(
            double frameWidth,
            double frameHeight,
            double x,
            double y)
        {
            double fill = Math.Max(frameWidth / Width, frameHeight / Height);
            double u = ((x - ((frameWidth - (Width * fill)) / 2)) / fill) - 0.5;
            double v = ((y - ((frameHeight - (Height * fill)) / 2)) / fill) - 0.5;
            int u0 = (int)Math.Floor(u);
            int v0 = (int)Math.Floor(v);
            double fu = u - u0;
            double fv = v - v0;
            double red = 0, green = 0, blue = 0;
            for (int dy = 0; dy <= 1; ++dy)
            {
                for (int dx = 0; dx <= 1; ++dx)
                {
                    double weight = (dx == 0 ? 1 - fu : fu) * (dy == 0 ? 1 - fv : fv);
                    int sx = Math.Clamp(u0 + dx, 0, Width - 1);
                    int sy = Math.Clamp(v0 + dy, 0, Height - 1);
                    int at = ((sy * Width) + sx) * 3;
                    red += Encoded[at] * weight;
                    green += Encoded[at + 1] * weight;
                    blue += Encoded[at + 2] * weight;
                }
            }
            return (red, green, blue);
        }

        private static byte ToByte(float value) =>
            (byte)Math.Clamp((int)Math.Round(value * 255, MidpointRounding.AwayFromZero), 0, 255);
    }

    /// <summary>
    /// 작은 BGRA8 그림을 흐립니다. macOS 는 Core Image 의 선형 작업 공간에서 흐리므로 여기서도
    /// sRGB 를 선형으로 펴서 흐린 뒤, 표본을 뽑을 때 다시 접습니다. 가장자리는 늘려 씁니다.
    /// </summary>
    public static BlurField? Blur(ReadOnlySpan<byte> bgra, int width, int height, double sigma = PrintWatermarkMetrics.BlurSigma)
    {
        if (width < 1 || height < 1 || bgra.Length < width * height * 4)
        {
            return null;
        }
        float[] linear = new float[width * height * 3];
        for (int index = 0, to = 0; to < linear.Length; index += 4, to += 3)
        {
            linear[to] = (float)Decode(bgra[index + 2] / 255.0);
            linear[to + 1] = (float)Decode(bgra[index + 1] / 255.0);
            linear[to + 2] = (float)Decode(bgra[index] / 255.0);
        }
        int radius = Math.Max(1, (int)Math.Ceiling(3 * sigma));
        float[] kernel = new float[(2 * radius) + 1];
        double sum = 0;
        for (int offset = -radius; offset <= radius; ++offset)
        {
            double weight = Math.Exp(-(offset * offset) / (2 * sigma * sigma));
            kernel[offset + radius] = (float)weight;
            sum += weight;
        }
        for (int index = 0; index < kernel.Length; ++index)
        {
            kernel[index] = (float)(kernel[index] / sum);
        }
        float[] horizontal = new float[linear.Length];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                float red = 0, green = 0, blue = 0;
                for (int offset = -radius; offset <= radius; ++offset)
                {
                    int at = ((y * width) + Math.Clamp(x + offset, 0, width - 1)) * 3;
                    float weight = kernel[offset + radius];
                    red += linear[at] * weight;
                    green += linear[at + 1] * weight;
                    blue += linear[at + 2] * weight;
                }
                int to = ((y * width) + x) * 3;
                horizontal[to] = red;
                horizontal[to + 1] = green;
                horizontal[to + 2] = blue;
            }
        }
        float[] result = new float[linear.Length];
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                float red = 0, green = 0, blue = 0;
                for (int offset = -radius; offset <= radius; ++offset)
                {
                    int at = ((Math.Clamp(y + offset, 0, height - 1) * width) + x) * 3;
                    float weight = kernel[offset + radius];
                    red += horizontal[at] * weight;
                    green += horizontal[at + 1] * weight;
                    blue += horizontal[at + 2] * weight;
                }
                int to = ((y * width) + x) * 3;
                result[to] = red;
                result[to + 1] = green;
                result[to + 2] = blue;
            }
        }
        return new BlurField(result, width, height);
    }

    private static double Decode(double value) =>
        value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);

    private static double Encode(double value)
    {
        value = Math.Clamp(value, 0, 1);
        return value <= 0.0031308 ? value * 12.92 : (1.055 * Math.Pow(value, 1 / 2.4)) - 0.055;
    }
}
