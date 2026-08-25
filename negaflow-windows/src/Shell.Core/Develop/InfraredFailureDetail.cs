namespace Negaflow.Shell;

/// <summary>
/// IR 검출이 <b>어디서</b> 실패했는지 사람이 읽는 말로 옮깁니다.
/// </summary>
/// <remarks>
/// 네이티브가 <c>nf_infrared_detection_summary_v1.reserved2</c> 에 실어 보내는 코드입니다.
/// 값은 <c>src/Native/abi/detect/infrared_file_detection.cpp</c> 의
/// <c>InfraredFileFailureDetail</c> 과 <b>한 자리도 어긋나면 안 됩니다</b> —
/// 시험이 그것을 지킵니다.
///
/// 이 표가 없으면 진단 기록에 <c>Unreadable</c> 한 낱말만 남아, 파일을 못 편 것인지 IR 을
/// 못 편 것인지 크기를 못 맞춘 것인지 가릴 수가 없습니다.
/// </remarks>
public static class InfraredFailureDetail
{
    public const uint None = 0U;
    public const uint EmptyPath = 1U;
    public const uint CancelledBeforeStart = 2U;
    public const uint VisibleFullConversionFailed = 3U;
    public const uint VisibleFastPathFailed = 4U;
    public const uint CancelledAfterVisible = 5U;
    public const uint CancelledBeforeStandardDecode = 6U;
    public const uint VisibleStandardDecodeFailed = 7U;
    public const uint VisibleStandardWorkingFailed = 8U;
    public const uint VisibleStandardExtractFailed = 9U;
    public const uint CancelledBeforeJoin = 10U;
    public const uint InfraredDecodeIncomplete = 11U;
    public const uint InfraredResampleFailed = 12U;
    public const uint AllocationFailed = 13U;
    public const uint UnexpectedException = 14U;

    /// <summary>진단 기록에 남길 말입니다. 모르는 값은 숫자를 그대로 냅니다.</summary>
    public static string Describe(uint detail) => detail switch
    {
        None => "none",
        EmptyPath => "empty-path",
        CancelledBeforeStart => "cancelled-before-start",
        VisibleFullConversionFailed => "visible-full-conversion-failed",
        VisibleFastPathFailed => "visible-fast-path-failed",
        CancelledAfterVisible => "cancelled-after-visible",
        CancelledBeforeStandardDecode => "cancelled-before-standard-decode",
        VisibleStandardDecodeFailed => "visible-standard-decode-failed",
        VisibleStandardWorkingFailed => "visible-standard-working-failed",
        VisibleStandardExtractFailed => "visible-standard-extract-failed",
        CancelledBeforeJoin => "cancelled-before-join",
        InfraredDecodeIncomplete => "infrared-decode-incomplete",
        InfraredResampleFailed => "infrared-resample-failed",
        AllocationFailed => "allocation-failed",
        UnexpectedException => "unexpected-exception",
        _ => detail.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };
}
