namespace Negaflow.Interop;

public sealed class DevelopExportResult
{
    public DevelopReferenceBase? ReferenceBase { get; internal set; }

    /// <summary>
    /// 요청이 <see cref="DevelopExportRequest.MeasureRangeShape"/> 를 켰고 측정이 성립했을 때만 채워집니다
    /// (기하평균 1). 한 채널이 밀도 상한에 닿았거나 비정상이면 비어 있습니다.
    /// </summary>
    public DevelopChannelRange? RangeShape { get; internal set; }
    public uint AppliedInputGammaMode { get; internal set; }
    public double AppliedInputGammaValue { get; internal set; }
    internal DevelopExportResult(
        bool succeeded,
        DevelopExportStage failedStage,
        string failureName,
        uint nativeErrorCode,
        uint cleanupErrorCode,
        uint imageWidth,
        uint imageHeight,
        FilmLookRoute filmLookRoute,
        bool filmLookColorApplied,
        bool filmLookAcutanceApplied,
        ulong sourceFileBytes,
        ulong outputFileBytes,
        ulong filmLookWorkspaceBytes,
        ulong wallMicroseconds,
        float appliedDminRed = 0,
        float appliedDminGreen = 0,
        float appliedDminBlue = 0,
        DevelopBaseSource baseSource = DevelopBaseSource.Manual,
        bool cancelled = false,
        FilmBaseMeasurementSnapshot? measurement = null,
        string? measurementMethod = null,
        DevelopDebugMetrics? debugMetrics = null)
    {
        Cancelled = cancelled;
        Succeeded = succeeded;
        FailedStage = failedStage;
        FailureName = failureName;
        NativeErrorCode = nativeErrorCode;
        CleanupErrorCode = cleanupErrorCode;
        ImageWidth = imageWidth;
        ImageHeight = imageHeight;
        FilmLookRoute = filmLookRoute;
        FilmLookColorApplied = filmLookColorApplied;
        FilmLookAcutanceApplied = filmLookAcutanceApplied;
        SourceFileBytes = sourceFileBytes;
        OutputFileBytes = outputFileBytes;
        FilmLookWorkspaceBytes = filmLookWorkspaceBytes;
        WallMicroseconds = wallMicroseconds;
        AppliedDminRed = appliedDminRed;
        AppliedDminGreen = appliedDminGreen;
        AppliedDminBlue = appliedDminBlue;
        BaseSource = baseSource;
        Measurement = measurement;
        MeasurementMethod = measurementMethod;
        DebugMetrics = debugMetrics;
    }

    /// <summary>
    /// 개발자 디버그 화면이 읽는 실측값입니다. 재지 않은 호출에서는 <c>null</c> 입니다.
    /// </summary>
    public DevelopDebugMetrics? DebugMetrics { get; }

    public bool Succeeded { get; }

    /// <summary>
    /// 호출자가 <see cref="DevelopRun.Cancel"/> 로 멈춘 실행입니다. 실패와 구분해야 하며,
    /// 취소된 실행은 파일도 미리보기 픽셀도 남기지 않습니다.
    /// </summary>
    public bool Cancelled { get; }

    public DevelopExportStage FailedStage { get; }

    /// <summary>
    /// The stage's own status name, not a translated message. Stable enough to log,
    /// switch on, and put in a bug report.
    /// </summary>
    public string FailureName { get; }

    public uint NativeErrorCode { get; }

    public uint CleanupErrorCode { get; }

    public uint ImageWidth { get; }

    public uint ImageHeight { get; }

    public FilmLookRoute FilmLookRoute { get; }

    public bool FilmLookColorApplied { get; }

    public bool FilmLookAcutanceApplied { get; }

    public ulong SourceFileBytes { get; }

    public ulong OutputFileBytes { get; }

    public ulong FilmLookWorkspaceBytes { get; }

    public ulong WallMicroseconds { get; }

    public float AppliedDminRed { get; }

    public float AppliedDminGreen { get; }

    public float AppliedDminBlue { get; }

    public DevelopBaseSource BaseSource { get; }

    /// <summary>
    /// 자동 네 실측 경로의 진단입니다. 수동·상수 폴백·광원 게인을 탄 프리셋은 null 입니다.
    /// </summary>
    public FilmBaseMeasurementSnapshot? Measurement { get; }

    /// <summary>
    /// 실측 방법의 Codable raw 값입니다. 진단이 광원 게인으로 빠져도 소스 이름에 씁니다.
    /// </summary>
    public string? MeasurementMethod { get; }
}

public readonly record struct DevelopReferenceBase(float Red, float Green, float Blue);

/// <summary>
/// 장치 × 필름의 채널 밀도 범위 모양 또는 교정값(R·G·B 곱, 기하평균 1). macOS
/// <c>DevelopParameters.channelRange</c> 와 같은 뜻입니다.
/// </summary>
public readonly record struct DevelopChannelRange(float Red, float Green, float Blue);
