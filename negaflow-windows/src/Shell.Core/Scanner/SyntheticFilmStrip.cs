using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 평판 위에 필름 스트립 한 줄을 올려놓고 훑은 프리뷰가 어떻게 보이는지 흉내 냅니다.
/// </summary>
/// <remarks>
/// 검출기는 밝기 자체가 아니라 **국부적인 디테일**로 필름 띠와 프레임을 가릅니다. 그래서 이
/// 그림은 세 가지를 분명히 갖춰야 합니다 — 디테일이 없는 밝은 빈 판, 그 안에 놓인 필름 띠,
/// 그리고 띠 안에서 디테일이 있는 프레임과 디테일이 없는 좁은 프레임 간격입니다. 한 장짜리
/// 장면으로는 검출기가 세는 대상이 아예 없어 "경로가 이어졌다" 이상을 말할 수 없습니다.
/// </remarks>
public static class SyntheticFilmStrip
{
    /// <summary>
    /// 프리뷰 밝기입니다. 값은 0...1 이며 검출기가 보는 것과 같은 정규화 범위입니다.
    /// </summary>
    /// <param name="frameCount">띠 안에 놓을 컷 수입니다.</param>
    public static float[] Luminance(
        int width,
        int height,
        double plateWidthMm,
        double plateHeightMm,
        FlatbedFrameFormat format,
        int frameCount)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(width, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(height, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(frameCount, 1);

        // 검출기의 축: 프레임은 **세로(Y)** 로 이어지고, 스트립의 폭은 가로(X) 입니다.
        double alongMm = FilmFrameFormats.StripWidthMm(format);
        double acrossMm = FilmFrameFormats.StripHeightMm(format);
        // 35mm 스트립의 실제 폭은 이미지 폭보다 넓습니다 — 위아래로 여백과 퍼포레이션이 있습니다.
        double stripAcrossMm = acrossMm * 1.45;
        double gapMm = alongMm * 0.06;

        double pixelsPerMmX = width / plateWidthMm;
        double pixelsPerMmY = height / plateHeightMm;
        double stripLeft = (plateWidthMm - stripAcrossMm) * 0.5;
        double frameLeft = (plateWidthMm - acrossMm) * 0.5;
        double totalMm = (frameCount * alongMm) + ((frameCount - 1) * gapMm);
        double firstTop = Math.Max(0.0, (plateHeightMm - totalMm) * 0.5);

        float[] luminance = new float[checked(width * height)];
        for (int y = 0; y < height; ++y)
        {
            double mmY = y / pixelsPerMmY;
            double intoStrip = mmY - firstTop;
            int index = (int)Math.Floor(intoStrip / (alongMm + gapMm));
            double withinCell = intoStrip - (index * (alongMm + gapMm));
            bool onFrameRow = index >= 0 && index < frameCount &&
                withinCell >= 0.0 && withinCell < alongMm;
            int row = y * width;
            for (int x = 0; x < width; ++x)
            {
                double mmX = x / pixelsPerMmX;
                if (mmX < stripLeft || mmX >= stripLeft + stripAcrossMm)
                {
                    // 빈 판. 램프가 그대로 보이므로 밝고 균일합니다 — 디테일이 없습니다.
                    luminance[row + x] = 0.97f;
                    continue;
                }
                bool insideFrame = onFrameRow &&
                    mmX >= frameLeft && mmX < frameLeft + acrossMm;
                if (!insideFrame)
                {
                    // 프레임 사이와 스트립 좌우 여백. 필름 베이스라 어둡고 균일합니다.
                    luminance[row + x] = 0.34f;
                    continue;
                }
                luminance[row + x] = FrameDetail(
                    withinCell / alongMm,
                    (mmX - frameLeft) / acrossMm,
                    index);
            }
        }
        return luminance;
    }

    /// <summary>
    /// 한 컷 안의 그림입니다. 검출기가 보는 것은 디테일이므로 값이 자주 바뀌어야 합니다 —
    /// 검출기는 **가로 이웃 차이**로 행의 디테일을 재므로 두 축 모두에서 값이 자주 바뀌어야
    /// 합니다 — 한 축으로만 변하는 그림은 검출기 눈에 빈 판과 같습니다.
    /// </summary>
    private static float FrameDetail(double u, double v, int index)
    {
        double alongStripes = Math.Sin(u * Math.PI * 12.0) * 0.16;
        double acrossStripes = Math.Sin(v * Math.PI * 9.0) * 0.16;
        double ramp = 0.5 + (u * 0.12) - (v * 0.08);
        double perFrame = ((index % 3) - 1) * 0.05;
        return (float)Math.Clamp(ramp + alongStripes + acrossStripes + perFrame, 0.05, 0.95);
    }
}
