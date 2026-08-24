namespace Negaflow.Shell.Develop;

/// <summary>
/// IR 결함 제거 한 번이 화면에 남기는 말입니다. macOS
/// <c>AppModel+InfraredDefectRemovalApplication.applyInfraredDetection</c> 의
/// <c>statusMessage</c> 분기를 그대로 옮긴 것입니다.
/// </summary>
/// <remarks>
/// 왜 문구가 아니라 열거인가 — 이 층은 지역화를 모릅니다. 어느 말을 할지만 정하고, 실제
/// 문구는 <c>Resources.resw</c> 에서 옵니다. 그래야 여섯 언어가 한 자리에서 관리됩니다.
/// </remarks>
public enum InfraredCleanMessage
{
    /// <summary>할 말이 없습니다. macOS 도 취소·중복 적용에는 아무 말도 하지 않습니다.</summary>
    None,

    /// <summary>macOS <c>infraredCleanDetectingStatus</c>.</summary>
    Detecting,

    /// <summary>macOS <c>infraredCleanAppliedFormat</c> — 제거한 결함 개수가 붙습니다.</summary>
    Applied,

    /// <summary>macOS <c>infraredCleanNoDefectsStatus</c>.</summary>
    NoDefects,

    /// <summary>macOS <c>infraredCleanCoverageAbortStatus</c>.</summary>
    CoverageAborted,

    /// <summary>macOS <c>AppInfraredText.unverifiedFilm</c> — 은염 흑백은 적외선을 막습니다.</summary>
    UnsupportedFilm,

    /// <summary>macOS <c>infraredCleanFailedStatus</c>.</summary>
    Failed,
}

/// <summary>고를 말과, 개수 서식에 넣을 값입니다.</summary>
public readonly record struct InfraredCleanStatus(InfraredCleanMessage Message, int DefectCount)
{
    public static InfraredCleanStatus Silent { get; } =
        new(InfraredCleanMessage.None, 0);

    public static InfraredCleanStatus Detecting { get; } =
        new(InfraredCleanMessage.Detecting, 0);

    /// <summary>
    /// 검출 한 번의 결과를 화면이 할 말로 옮깁니다. macOS 와 같은 분기이며, 성공했는데
    /// 성분이 하나도 없으면 "찾지 못했다" 로 내려앉는 것까지 같습니다.
    /// </summary>
    public static InfraredCleanStatus From(InfraredDefectApplyResult? result)
    {
        if (result is null)
        {
            return Silent;
        }
        return result.Status switch
        {
            InfraredDefectApplyStatus.Applied =>
                result.Detection is { Components.Count: > 0 } detection
                    ? new InfraredCleanStatus(
                        InfraredCleanMessage.Applied,
                        detection.Components.Count)
                    : new InfraredCleanStatus(InfraredCleanMessage.NoDefects, 0),
            InfraredDefectApplyStatus.NoDefects =>
                new InfraredCleanStatus(InfraredCleanMessage.NoDefects, 0),
            InfraredDefectApplyStatus.CoverageTooHigh =>
                new InfraredCleanStatus(InfraredCleanMessage.CoverageAborted, 0),
            InfraredDefectApplyStatus.UnsupportedFilm =>
                new InfraredCleanStatus(InfraredCleanMessage.UnsupportedFilm, 0),
            // 취소와 중복 적용은 macOS 도 조용합니다 — 사용자가 한 일이거나, 이미 붙어 있는
            // 레이어를 다시 붙이지 않은 것뿐입니다.
            InfraredDefectApplyStatus.Cancelled or
            InfraredDefectApplyStatus.AlreadyApplied =>
                Silent,
            _ => new InfraredCleanStatus(InfraredCleanMessage.Failed, 0),
        };
    }
}
