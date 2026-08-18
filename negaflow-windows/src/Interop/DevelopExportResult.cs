namespace Negaflow.Interop;

public sealed class DevelopExportResult
{
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
        bool cancelled = false)
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
    }

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
}
