using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Localization;

/// <summary>
/// 현상·내보내기 결과를 <b>화면에 적을 문구</b>로 바꿉니다.
/// </summary>
/// <remarks>
/// <para>
/// 값은 <c>Shell.Core</c> 가 만들고 문구는 여기서 만듭니다 — <see cref="InfraredCleanStatusText"/>
/// 와 같은 자리입니다. <c>Shell.Core</c> 는 <see cref="AppResources"/> 를 볼 수 없고, 봐서도
/// 안 됩니다(UI 없이 시험되는 계층입니다).
/// </para>
/// <para>
/// <c>DevelopPanelState.Describe</c> 는 남아 있지만 그쪽은 <b>기록용</b>입니다. 로그는 어느
/// 언어로 앱을 켰든 같은 글자여야 읽고 비교할 수 있으므로 번역하지 않습니다.
/// </para>
/// <para>
/// 엔진이 실패한 자리(<c>FailedStage</c>)와 이유(<c>FailureName</c>)는 엔진이 내는 식별자라
/// 그대로 붙입니다 — macOS <c>exportFailedFormat</c>("Export failed: %@") 도 엔진 메시지를
/// 그대로 넣습니다.
/// </para>
/// </remarks>
public static class DevelopExportOutcomeText
{
    public static string For(DevelopExportOutcome outcome)
    {
        ArgumentNullException.ThrowIfNull(outcome);
        switch (outcome.Kind)
        {
            case DevelopExportOutcomeKind.Completed when outcome.Result is { } result:
                return result.Succeeded
                    ? AppResources.FormatIntegers(
                        "developExportCompleteFormat",
                        "Text",
                        (int)result.ImageWidth,
                        (int)result.ImageHeight,
                        (int)Math.Round(result.WallMicroseconds / 1000.0))
                    : AppResources.FormatText(
                        "developExportFailedFormat",
                        "Text",
                        $"{result.FailedStage}: {result.FailureName}");

            case DevelopExportOutcomeKind.Refused:
                return Refused(outcome.Refusal);

            case DevelopExportOutcomeKind.Faulted:
                return AppResources.FormatText(
                    "developExportEngineFailedFormat",
                    "Text",
                    outcome.FaultMessage ?? string.Empty);

            case DevelopExportOutcomeKind.Busy:
                return AppResources.Get("developExportBusy", "Text");

            default:
                return AppResources.Get("developExportNoResult", "Text");
        }
    }

    /// <summary>
    /// 거절 사유를 문구로 바꿉니다.
    /// </summary>
    /// <remarks>
    /// 키를 변수로 모아 두고 한 번만 <c>Get</c> 하면 짧아지지만, <c>check-localized-keys.py</c>
    /// 는 인자가 <b>글자 그대로 적힌</b> 호출만 읽습니다. 계산해서 넘긴 키는 검사에서 빠지고,
    /// 빠진 키는 빌드를 통과한 뒤 <b>실행 중에 창을 죽입니다.</b> 그래서 가지마다 키를 그대로
    /// 적습니다.
    /// </remarks>
    private static string Refused(DevelopRequestRefusal refusal) => refusal switch
    {
        DevelopRequestRefusal.NoFrameSelected =>
            AppResources.Get("developExportRefusedNoFrame", "Text"),
        DevelopRequestRefusal.UnsupportedBaseEstimationMode =>
            AppResources.Get("developExportRefusedBaseMode", "Text"),
        DevelopRequestRefusal.UnsupportedDigitalSource =>
            AppResources.Get("developExportRefusedDigitalSource", "Text"),
        DevelopRequestRefusal.UnsupportedPositiveFilm =>
            AppResources.Get("developExportRefusedPositiveFilm", "Text"),
        DevelopRequestRefusal.InvalidDestination =>
            AppResources.Get("developExportRefusedDestination", "Text"),
        DevelopRequestRefusal.UnknownOutputFormat =>
            AppResources.Get("developExportRefusedOutputFormat", "Text"),
        DevelopRequestRefusal.StaleDefectSource =>
            AppResources.Get("developExportRefusedStaleDefectSource", "Text"),
        _ => AppResources.Get("developExportRefused", "Text"),
    };
}
