namespace Negaflow.Shell.Library;

/// <summary>
/// 정착한 미리보기 픽셀을 썸네일 크기로 줄입니다.
/// </summary>
/// <remarks>
/// 미리보기 버퍼는 수 MB 이고 UI 스레드가 들고 있습니다. 그대로 복사해 워커로 넘기면 슬라이더를
/// 끄는 내내 그만큼을 복사하게 되므로, 여기서 먼저 줄여 놓고 압축만 워커로 보냅니다. 상자 필터
/// 한 번이면 충분합니다 — 카드 크기에서 더 좋은 필터와 구별되지 않고, 화면에 나가는 현상 결과는
/// 이 경로를 지나지 않습니다.
/// </remarks>
public static class ThumbnailScaler
{
    /// <summary>
    /// 긴 변이 <paramref name="maximumDimension"/> 이하가 되도록 정수 배율로 줄입니다.
    /// 이미 작으면 그대로 복사합니다.
    /// </summary>
    public static byte[] Reduce(
        ReadOnlySpan<byte> bgra,
        int width,
        int height,
        int maximumDimension,
        out int reducedWidth,
        out int reducedHeight)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumDimension);
        if (bgra.Length < (long)width * height * 4)
        {
            throw new ArgumentException("The pixel span is smaller than the stated image.", nameof(bgra));
        }

        int factor = 1;
        while (Math.Max(width, height) / (factor + 1) >= maximumDimension && factor < 64)
        {
            ++factor;
        }
        // 정수 배율만으로는 상한을 넘길 수 있으므로 한 칸 더 줄입니다.
        while (Math.Max(width / factor, height / factor) > maximumDimension && factor < 64)
        {
            ++factor;
        }

        reducedWidth = Math.Max(1, width / factor);
        reducedHeight = Math.Max(1, height / factor);
        byte[] output = new byte[reducedWidth * reducedHeight * 4];
        if (factor == 1)
        {
            bgra[..output.Length].CopyTo(output);
            return output;
        }

        int samples = factor * factor;
        for (int y = 0; y < reducedHeight; ++y)
        {
            int sourceTop = y * factor;
            int outputRow = y * reducedWidth * 4;
            for (int x = 0; x < reducedWidth; ++x)
            {
                int sourceLeft = x * factor;
                int blue = 0;
                int green = 0;
                int red = 0;
                int alpha = 0;
                for (int dy = 0; dy < factor; ++dy)
                {
                    int rowStart = ((sourceTop + dy) * width + sourceLeft) * 4;
                    for (int dx = 0; dx < factor; ++dx)
                    {
                        int offset = rowStart + (dx * 4);
                        blue += bgra[offset];
                        green += bgra[offset + 1];
                        red += bgra[offset + 2];
                        alpha += bgra[offset + 3];
                    }
                }
                int target = outputRow + (x * 4);
                output[target] = (byte)(blue / samples);
                output[target + 1] = (byte)(green / samples);
                output[target + 2] = (byte)(red / samples);
                output[target + 3] = (byte)(alpha / samples);
            }
        }
        return output;
    }
}
