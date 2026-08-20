using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Localization;

/// <summary>
/// IR 결함 제거 결과를 사용자가 읽을 한 줄로 바꿉니다. macOS
/// <c>applyInfraredDetection</c> 이 <c>statusMessage</c> 에 넣는 문구와 같습니다.
/// </summary>
public static class InfraredCleanStatusText
{
    /// <summary>할 말이 없으면 빈 문자열입니다 — 앞의 문구를 지우는 것이 맞습니다.</summary>
    public static string For(InfraredCleanStatus status) =>
        status.Message switch
        {
            InfraredCleanMessage.Applied => AppResources.FormatIntegers(
                "developInfraredCleanAppliedFormat",
                "Value",
                status.DefectCount),
            InfraredCleanMessage.NoDefects =>
                AppResources.Get("developInfraredCleanNoDefects", "Text"),
            InfraredCleanMessage.CoverageAborted =>
                AppResources.Get("developInfraredCleanCoverageAbort", "Text"),
            InfraredCleanMessage.UnsupportedFilm =>
                AppResources.Get("developInfraredCleanSkippedBW", "Text"),
            InfraredCleanMessage.Failed =>
                AppResources.Get("developInfraredCleanFailed", "Text"),
            _ => string.Empty,
        };
}
