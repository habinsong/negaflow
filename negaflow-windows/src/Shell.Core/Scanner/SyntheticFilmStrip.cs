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
    /// <param name="frame">한 컷의 치수입니다. 규격이든 수동 비율이든 같습니다.</param>
    /// <param name="frameCount">띠 안에 놓을 컷 수입니다.</param>
    public static float[] Luminance(
        int width,
        int height,
        double plateWidthMm,
        double plateHeightMm,
        FlatbedFrameDimensions frame,
        int frameCount)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(width, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(height, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(frameCount, 1);

        // 검출기의 축: 프레임은 **세로(Y)** 로 이어지고, 스트립의 폭은 가로(X) 입니다.
        double alongMm = frame.AlongMm;
        double acrossMm = frame.AcrossMm;
        // 필름의 실제 폭입니다. 35mm 는 이미지(24mm) 위아래로 여백과 퍼포레이션이 있어 35mm,
        // 120 은 이미지(56mm)보다 조금 넓은 61mm 입니다. 예전 판은 120 도 이미지 × 1.45(81mm)로
        // 그려, 슬롯 옆 표본이 유리 대신 필름 베이스를 읽고 컷 사이 간격이 띠로 보이지 않았습니다.
        double stripAcrossMm = Math.Max(acrossMm + 2.0, frame.Is35mm ? 35.0 : 61.0);
        double gapMm = GapMm(frame);

        double pixelsPerMmX = width / plateWidthMm;
        double pixelsPerMmY = height / plateHeightMm;
        double stripLeft = (plateWidthMm - stripAcrossMm) * 0.5;
        double frameLeft = (plateWidthMm - acrossMm) * 0.5;
        double totalMm = (frameCount * alongMm) + ((frameCount - 1) * gapMm);
        double firstTop = Math.Max(0.0, (plateHeightMm - totalMm) * 0.5);
        // 필름은 잘린 길이만큼만 판 위에 있습니다(앞뒤 여유는 간격 한 칸). 예전 판은 베이스를
        // 판 길이 전체로 깔아 빈 베이스까지 컷으로 셌습니다. macOS 목업도 컷 자리만 그립니다.
        double stripTop = firstTop - gapMm;
        double stripBottom = firstTop + totalMm + gapMm;

        float[] luminance = new float[checked(width * height)];
        for (int y = 0; y < height; ++y)
        {
            double mmY = y / pixelsPerMmY;
            bool onStrip = mmY >= stripTop && mmY < stripBottom;
            double intoStrip = mmY - firstTop;
            int index = (int)Math.Floor(intoStrip / (alongMm + gapMm));
            double withinCell = intoStrip - (index * (alongMm + gapMm));
            bool onFrameRow = index >= 0 && index < frameCount &&
                withinCell >= 0.0 && withinCell < alongMm;
            int row = y * width;
            for (int x = 0; x < width; ++x)
            {
                double mmX = x / pixelsPerMmX;
                if (!onStrip || mmX < stripLeft || mmX >= stripLeft + stripAcrossMm)
                {
                    // 빈 판. 램프가 그대로 보이므로 밝고 균일합니다 — 디테일이 없습니다.
                    luminance[row + x] = 0.97f + SensorNoise(x, y);
                    continue;
                }
                bool insideFrame = onFrameRow &&
                    mmX >= frameLeft && mmX < frameLeft + acrossMm;
                if (!insideFrame)
                {
                    // 프레임 사이와 스트립 좌우 여백. 필름 베이스라 어둡고 균일합니다.
                    luminance[row + x] = 0.34f + SensorNoise(x, y);
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
    /// 센서 잡음입니다(±0.002). 실제 프리뷰는 빈 유리와 필름 베이스에도 잡음이 있고, 검출기는
    /// 그 잡음을 바닥으로 삼아 빈 칸을 거릅니다(<c>occupied</c>). 잡음이 0 이면 그 거르기가
    /// 꺼져, 고정 피치인 35mm 격자가 빈 베이스 위로 판 끝까지 뻗었습니다 — FF 3컷을 그리면
    /// 7컷을 셌습니다. 값은 좌표로 정해지므로 그림은 매번 같습니다.
    /// </summary>
    private static float SensorNoise(int x, int y)
    {
        uint bits = unchecked(((uint)x * 73_856_093U) ^ ((uint)y * 19_349_663U));
        return ((bits & 0xffU) / 255.0f - 0.5f) * 0.004f;
    }

    /// <summary>
    /// 컷 사이 간격입니다. 35mm 는 퍼포레이션 이송이 정하므로 고정(38mm 피치 → 2mm)이고,
    /// 120 은 카메라마다 달라 검출기가 받는 2–9mm 안쪽의 4mm 로 둡니다.
    /// </summary>
    /// <remarks>
    /// 예전 판은 <c>컷 길이 × 0.06</c> 이었습니다. 65×24 는 3.9mm 가 되어 35mm 간격 범위
    /// (1.0–3.5mm)를 벗어나 데모 자동 검출이 실패했고, 6×17 은 10.1mm 로 120 범위도 넘었습니다.
    /// </remarks>
    public static double GapMm(FlatbedFrameDimensions frame) => frame.Is35mm ? 2.0 : 4.0;

    /// <summary>
    /// 판 위 한 줄에 놓을 수 있는 컷 수입니다. <paramref name="maximum"/> 를 넘지 않고, 긴 컷도
    /// 한 장은 놓습니다 — 판 밖으로 넘친 컷은 검출기가 반쪽으로 봅니다.
    /// </summary>
    public static int FittingFrameCount(
        double plateLengthMm,
        FlatbedFrameDimensions frame,
        int maximum)
    {
        double gap = GapMm(frame);
        int fitting = (int)Math.Floor((plateLengthMm + gap) / (frame.AlongMm + gap));
        return Math.Clamp(fitting, 1, Math.Max(1, maximum));
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
