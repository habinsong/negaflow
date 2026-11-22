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
    /// <summary>
    /// 인화 화면 프루프의 목적지 ICC 와 용지 시뮬레이션 여부입니다. 없으면
    /// <see langword="null"/> 입니다.
    /// </summary>
    /// <remarks>
    /// macOS <c>displaySoftProofSettings(for:in: .print)</c> 와 같습니다 — C-print 미리보기가
    /// 켜져 있으면 랩 프루프(용지는 인화용지 시뮬레이션 스위치), 아니면 인화 내보내기가 실제로
    /// 굽는 프린터 출력 프로파일(용지는 전역 소프트 프루프의 "용지와 잉크"). 앞 판은 표준
    /// 공정에서 프루프가 아예 꺼졌습니다.
    /// </remarks>
    public static (string Path, bool PaperSimulation)? Destination(
        PrintPreferences print,
        SoftProofPreferences? softProof)
    {
        ArgumentNullException.ThrowIfNull(print);
        if (print.OutputProcess == PrintOutputProcess.CPrint &&
            print.CPrintPreviewEnabled &&
            print.CPrintProofProfilePath.Length > 0)
        {
            return (print.CPrintProofProfilePath, print.CPrintPaperSimulationEnabled);
        }
        if (softProof is { PrinterProfilePath.Length: > 0 } printer)
        {
            return (printer.PrinterProfilePath,
                printer.Simulation == SoftProofSimulation.PaperAndBlackInk);
        }
        return null;
    }

    /// <summary>인화 화면의 프루프 설정입니다. 걸리지 않으면 <see langword="null"/> 입니다.</summary>
    public static SoftProofSettings? Settings(PrintPreferences print, SoftProofPreferences? softProof = null)
    {
        ArgumentNullException.ThrowIfNull(print);
        if (Destination(print, softProof) is not { } destination)
        {
            return null;
        }
        // 태그를 직접 읽습니다. 시스템 판독기는 인화소가 주는 표(LUT) 기반 프로파일에서
        // 아무것도 돌려주지 않아, 프로파일을 걸어도 용지와 사진이 그대로였습니다.
        if (PrintIccProfile.ReadMedia(destination.Path) is not { } media)
        {
            return null;
        }
        return new SoftProofSettings(
            true,
            // 용지 흰색·잉크 검정은 용지 시뮬레이션을 켰을 때만 화소에 겁니다. 앞 판은 늘
            // 걸어서, 미리보기만 켜도 썸네일이 용지 색으로 눌렸습니다.
            destination.PaperSimulation
                ? SoftProofSimulation.PaperAndBlackInk
                : SoftProofSimulation.ProfileOnly,
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
    /// <remarks>
    /// 계수는 <b>선형</b> 작업 공간의 배율입니다(macOS 는 선형 작업 공간의
    /// <c>CIColorMatrix</c>). sRGB 바이트에 그대로 곱하면 같은 용지가 더 어둡게 눌리므로,
    /// 바이트를 선형으로 풀어 곱하고 다시 인코딩합니다.
    /// </remarks>
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
        // 채널마다 입력 바이트 하나가 출력 바이트 하나로 정해지므로 256 칸 표 셋으로 끝냅니다.
        // 화소마다 pow 를 부르지 않습니다.
        Span<byte> blue = stackalloc byte[256];
        Span<byte> green = stackalloc byte[256];
        Span<byte> red = stackalloc byte[256];
        for (int code = 0; code < 256; ++code)
        {
            double linear = DecodeSrgb(code / 255.0);
            blue[code] = EncodeSrgbByte((linear * scaleBlue) + proof.BlackInk.Blue);
            green[code] = EncodeSrgbByte((linear * scaleGreen) + proof.BlackInk.Green);
            red[code] = EncodeSrgbByte((linear * scaleRed) + proof.BlackInk.Red);
        }
        for (int index = 0; index + 3 < pixels.Length; index += 4)
        {
            pixels[index] = blue[pixels[index]];
            pixels[index + 1] = green[pixels[index + 1]];
            pixels[index + 2] = red[pixels[index + 2]];
        }
    }

    /// <summary>
    /// 선형 값(용지 흰색 등)을 화면에 칠할 sRGB 바이트로 옮깁니다. 용지 흰색은 선형 배율이라
    /// 그대로 바이트로 쓰면 사진 속 흰색보다 어두운 여백이 나옵니다(L95 용지 224 대 241).
    /// </summary>
    public static byte EncodeSrgbByte(double linear)
    {
        double value = Math.Clamp(linear, 0, 1);
        double encoded = value <= 0.0031308
            ? value * 12.92
            : (1.055 * Math.Pow(value, 1 / 2.4)) - 0.055;
        return (byte)Math.Clamp(Math.Round(encoded * 255.0), 0, 255);
    }

    private static double DecodeSrgb(double value) =>
        value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);
    /// <summary>
    /// 현상 요청에 실어 보낼 프루프입니다. macOS <c>cPrintSoftProofSettings</c> 그대로이며,
    /// 색영역 경고까지 함께 담습니다.
    /// </summary>
    /// <remarks>
    /// 화소를 손으로 흉내 내는 <see cref="Apply"/> 와 달리, 이 값은 <b>현상 엔진</b>이 씁니다 —
    /// 프로파일 변환도 색역 판정도 ICM 이 합니다. 근사하면 맥과 다른 화소가 표시됩니다.
    /// </remarks>
    public static SoftProofSettings? Preview(
        PrintPreferences print,
        bool warnOutOfGamut,
        SoftProofPreferences? softProof = null)
    {
        ArgumentNullException.ThrowIfNull(print);
        if (Destination(print, softProof) is not { } destination ||
            PrintIccProfile.ReadMedia(destination.Path) is not { } media)
        {
            return null;
        }
        return new SoftProofSettings(
            true,
            // 용지 시뮬레이션을 켜야 용지 흰색·잉크 검정까지 흉내 냅니다.
            destination.PaperSimulation
                ? SoftProofSimulation.PaperAndBlackInk
                : SoftProofSimulation.ProfileOnly,
            new SoftProofRgb(media.White[0], media.White[1], media.White[2]),
            new SoftProofRgb(media.Black[0], media.Black[1], media.Black[2]),
            // 인화 타일의 색역 경고는 `PrintPreviewRenderer` 가 프루프 ICC 로 직접 판정합니다.
            // 엔진에 경고를 켜 보내면 ICC 가 없는 이 설정으로 엔진이 출력 색공간 기준 경고를
            // 먼저 구워, 그 빨강이 유리건판·청사진 변환과 ICC 판정을 한 번 더 지났습니다.
            warnOutOfGamut: false);
    }
}
