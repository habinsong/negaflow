namespace Negaflow.Shell.Develop;

/// <summary>
/// 화면에 올라간 화소의 생김새를 한 줄로 적습니다. 두 화면이 <b>같은 그림</b>을 보고 있는지
/// 눈이 아니라 수로 가리기 위한 것입니다.
/// </summary>
/// <remarks>
/// 평균과 최소·최대를 같이 냅니다. 자동 레벨이 걸린 그림은 채널마다 끝까지 늘어나 최소가 0,
/// 최대가 255 에 붙고 평균이 중립 쪽으로 옮겨 가므로, 걸리지 않은 그림과 수로 갈립니다.
/// 26MB 버퍼를 매번 다 훑으면 느리므로 화소를 건너뛰며 봅니다 — 통계값은 그대로입니다.
/// </remarks>
public static class PreviewPixelStats
{
    /// <summary>몇 화소마다 하나를 볼지입니다. 2560x2560 에서 약 4만 개를 봅니다.</summary>
    private const int Step = 163;

    public static string Describe(ReadOnlySpan<byte> bgra, int width, int height)
    {
        long pixels = (long)width * height;
        if (width <= 0 || height <= 0 || bgra.Length < pixels * 4)
        {
            return "stats=none";
        }
        long sumB = 0;
        long sumG = 0;
        long sumR = 0;
        int minB = 255;
        int minG = 255;
        int minR = 255;
        int maxB = 0;
        int maxG = 0;
        int maxR = 0;
        long seen = 0;
        for (long index = 0; index < pixels; index += Step)
        {
            int at = (int)(index * 4);
            int b = bgra[at];
            int g = bgra[at + 1];
            int r = bgra[at + 2];
            sumB += b;
            sumG += g;
            sumR += r;
            minB = Math.Min(minB, b);
            minG = Math.Min(minG, g);
            minR = Math.Min(minR, r);
            maxB = Math.Max(maxB, b);
            maxG = Math.Max(maxG, g);
            maxR = Math.Max(maxR, r);
            ++seen;
        }
        if (seen == 0)
        {
            return "stats=none";
        }
        string mean = System.FormattableString.Invariant(
            $"mean={(double)sumR / seen:F1}/{(double)sumG / seen:F1}/{(double)sumB / seen:F1}");
        string range = System.FormattableString.Invariant(
            $"min={minR}/{minG}/{minB} max={maxR}/{maxG}/{maxB} n={seen}");
        return mean + " " + range;
    }
}
