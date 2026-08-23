using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Print;

/// <summary>
/// 프루프가 계산한 <b>용지 흰색</b>입니다. macOS <c>SoftProof.simulatedPaperWhiteRGB(for:)</c>
/// 와 같은 조건·같은 값입니다.
/// </summary>
/// <remarks>
/// macOS 는 이 값을 인화 지면의 바탕색으로 씁니다 — <c>PrintCanvasView.paperColor</c> 가
/// <c>pageBackgroundColor</c> 의 <c>.white</c> 자리에 들어갑니다. 그래서 인화소 프로파일을
/// 걸고 용지 시뮬레이션을 켜면 <b>종이 자체가</b> 그 인화지의 흰색으로 물듭니다.
///
/// 조건도 macOS 그대로입니다: 프루프가 켜져 있고, 시뮬레이션이 "용지와 잉크" 이고, 프로파일에
/// 매체 흰색이 있을 때만 값이 나옵니다. 하나라도 어긋나면 순백입니다.
/// </remarks>
public static class PrintPaperTint
{
    /// <summary>
    /// 지금 설정으로 물든 용지 흰색입니다. 물들지 않으면 <see langword="null"/> 입니다.
    /// </summary>
    public static SoftProofRgb? For(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        // macOS 는 흰 종이일 때만 프루프가 계산한 종이 흰색을 씁니다. 그리고 인화 화면은
        // 전역 프루프가 아니라 <b>C-print 설정</b>을 봅니다
        // (`displaySoftProofSettings(for:in: .print)` → `cPrintSoftProofSettings`).
        // 용지는 <b>인화용지 시뮬레이션</b>을 켰을 때만 물듭니다 — 미리보기만 켜면 사진에만
        // 걸립니다(macOS `simulatedPaperWhiteRGB` 가 `.paperAndBlackInk` 를 요구합니다).
        if (print.SheetBackground != PrintSheetBackground.White ||
            !print.CPrintPaperSimulationEnabled ||
            PrintSoftProofFilter.Settings(print) is not { } proof)
        {
            return null;
        }
        SoftProofRgb white = proof.PaperWhite;
        // 값이 사실상 순백이면 물들이지 않습니다 — 눈에 보이지도 않으면서 판만 다시 그립니다.
        return Math.Abs(white.Red - 1) < 0.002 &&
            Math.Abs(white.Green - 1) < 0.002 &&
            Math.Abs(white.Blue - 1) < 0.002
            ? null
            : white;
    }
}
