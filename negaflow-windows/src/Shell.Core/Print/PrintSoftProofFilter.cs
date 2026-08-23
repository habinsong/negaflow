using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Print;

/// <summary>
/// 인화 화면이 쓰는 프루프입니다. macOS <c>AppModel.cPrintSoftProofSettings</c> 와
/// <c>SoftProof.apply(to:using:)</c> 를 옮긴 것입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS <c>displaySoftProofSettings(for:in:)</c> 은 인화 작업공간에서 <b>전역 프루프가
/// 아니라</b> C-print 전용 설정을 씁니다. 그래서 설정 화면의 소프트 프루프를 켜지 않아도
/// 인화 미리보기가 인화소 프로파일로 보입니다.
/// </para>
/// <para>
/// 화소 계산은 macOS <c>CIColorMatrix</c> 한 번과 같습니다 —
/// <c>출력 = 입력 × (용지흰색 − 잉크검정) + 잉크검정</c>. 용지 시뮬레이션을 끄면
/// (<c>profileOnly</c>) 화소는 건드리지 않습니다.
/// </para>
/// </remarks>
public static class PrintSoftProofFilter
{
    /// <summary>인화 화면의 프루프 설정입니다. 걸리지 않으면 <see langword="null"/> 입니다.</summary>
    public static SoftProofSettings? Settings(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        // 미리보기 스위치가 프루프 자체를 켭니다 — 그때 <b>사진</b>에 프로파일이 걸립니다.
        // 용지 시뮬레이션은 그 위에 <b>용지</b>까지 물들이는 별개의 스위치입니다.
        if (print.OutputProcess != PrintOutputProcess.CPrint ||
            !print.CPrintPreviewEnabled ||
            print.CPrintProofProfilePath.Length == 0)
        {
            return null;
        }
        // 태그를 직접 읽습니다. 시스템 판독기는 인화소가 주는 표(LUT) 기반 프로파일에서
        // 아무것도 돌려주지 않아, 프로파일을 걸어도 용지와 사진이 그대로였습니다.
        if (PrintIccProfile.ReadMedia(print.CPrintProofProfilePath) is not { } media)
        {
            return null;
        }
        return new SoftProofSettings(
            true,
            SoftProofSimulation.PaperAndBlackInk,
            new SoftProofRgb(media.White[0], media.White[1], media.White[2]),
            new SoftProofRgb(media.Black[0], media.Black[1], media.Black[2]));
    }

    /// <summary>이 설정이 화소를 실제로 바꾸는지입니다.</summary>
    public static bool Transforms(SoftProofSettings? settings) =>
        settings is { IsEnabled: true, Simulation: SoftProofSimulation.PaperAndBlackInk } &&
        (Math.Abs(settings.PaperWhite.Red - 1) > 0.002 ||
         Math.Abs(settings.PaperWhite.Green - 1) > 0.002 ||
         Math.Abs(settings.PaperWhite.Blue - 1) > 0.002 ||
         settings.BlackInk.Red > 0.002 ||
         settings.BlackInk.Green > 0.002 ||
         settings.BlackInk.Blue > 0.002);

    /// <summary>
    /// BGRA8 화소 묶음에 프루프를 겁니다. macOS <c>SoftProof.apply(to:using:)</c> 과 같은
    /// 한 번의 선형 변환입니다.
    /// </summary>
    public static void Apply(Span<byte> pixels, SoftProofSettings? settings)
    {
        if (!Transforms(settings))
        {
            return;
        }
        SoftProofSettings proof = settings!;
        // macOS: `scale = max(0, white - black)`, `bias = black`.
        double scaleRed = Math.Max(0, proof.PaperWhite.Red - proof.BlackInk.Red);
        double scaleGreen = Math.Max(0, proof.PaperWhite.Green - proof.BlackInk.Green);
        double scaleBlue = Math.Max(0, proof.PaperWhite.Blue - proof.BlackInk.Blue);
        for (int index = 0; index + 3 < pixels.Length; index += 4)
        {
            pixels[index] = Channel((pixels[index] / 255.0 * scaleBlue) + proof.BlackInk.Blue);
            pixels[index + 1] =
                Channel((pixels[index + 1] / 255.0 * scaleGreen) + proof.BlackInk.Green);
            pixels[index + 2] =
                Channel((pixels[index + 2] / 255.0 * scaleRed) + proof.BlackInk.Red);
        }
    }

    private static byte Channel(double value) =>
        (byte)Math.Clamp(Math.Round(value * 255.0), 0, 255);
    /// <summary>
    /// 현상 요청에 실어 보낼 프루프입니다. macOS <c>cPrintSoftProofSettings</c> 그대로이며,
    /// 색영역 경고까지 함께 담습니다.
    /// </summary>
    /// <remarks>
    /// 화소를 손으로 흉내 내는 <see cref="Apply"/> 와 달리, 이 값은 <b>현상 엔진</b>이 씁니다 —
    /// 프로파일 변환도 색역 판정도 ICM 이 합니다. 근사하면 맥과 다른 화소가 표시됩니다.
    /// </remarks>
    public static SoftProofSettings? Preview(PrintPreferences print, bool warnOutOfGamut)
    {
        ArgumentNullException.ThrowIfNull(print);
        if (print.OutputProcess != PrintOutputProcess.CPrint ||
            !print.CPrintPreviewEnabled ||
            print.CPrintProofProfilePath.Length == 0 ||
            PrintIccProfile.ReadMedia(print.CPrintProofProfilePath) is not { } media)
        {
            return null;
        }
        return new SoftProofSettings(
            true,
            // 용지 시뮬레이션을 켜야 용지 흰색·잉크 검정까지 흉내 냅니다.
            print.CPrintPaperSimulationEnabled
                ? SoftProofSimulation.PaperAndBlackInk
                : SoftProofSimulation.ProfileOnly,
            new SoftProofRgb(media.White[0], media.White[1], media.White[2]),
            new SoftProofRgb(media.Black[0], media.Black[1], media.Black[2]),
            warnOutOfGamut);
    }
}
