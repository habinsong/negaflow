using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 카탈로그를 열지 못했을 때 사용자가 빠져나갈 길입니다. macOS
/// <c>AppModel+LibraryRecovery</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 여기 있는 것들은 <b>document 가 없을 때에도</b> 돌아야 합니다 — 못 열었을 때 쓰는
/// 자리이기 때문입니다. 열기에 실패하면 <see cref="LibraryDocumentOpener"/> 가 세션을
/// 놓아 주므로, 그때는 잠깐 새 세션을 열어 일을 처리하고 다시 놓습니다.
/// </remarks>
public sealed partial class LibraryHostService
{
    /// <summary>
    /// 열려고 시도한 자리입니다. <see cref="StorageRoots"/> 와 달리 <b>실패해도</b>
    /// 남습니다 — 무엇을 열려다 실패했는지 모르면 복구 화면이 아무 것도 보여 줄 수 없습니다.
    /// </summary>
    public StorageRootSet? AttemptedRoots { get; private set; }

    /// <summary>
    /// 이 버전이 <b>읽지 못한</b> 사진 수입니다. 그 사진들은 목록에서 빠지지만
    /// <c>payload</c> 는 그대로 보존되어 다음 저장에 다시 쓰입니다 — 파일도 카탈로그도
    /// 지워지지 않습니다. 사용자에게 그 사실을 알리는 것이 이 숫자의 몫입니다.
    /// </summary>
    public int UnreadableFrameCount => Issues.Count;

    /// <summary>
    /// 필드 하나를 되돌려 <b>살린</b> 사진의 수리 코드별 개수입니다. 이 사진들은 목록에
    /// 그대로 있습니다 — macOS <c>repairSummary</c> 자리입니다.
    /// </summary>
    public IReadOnlyList<string> FrameRepairCodes() =>
        Count(document?.Repairs ?? []);

    /// <summary>
    /// 읽지 못한 까닭을 코드별 개수로 셉니다. 진단에만 담습니다 — 사진 id 는 담지 않습니다.
    /// </summary>
    public IReadOnlyList<string> FrameIssueCodes() =>
        Count(Issues.Select(issue => issue.RouteError == DevelopRouteError.None
            ? issue.Error.ToString()
            : $"{issue.Error}:{issue.RouteError}"));

    /// <summary>코드별 개수를 <c>code=count</c> 로 셉니다. 차례는 항상 같습니다.</summary>
    private static IReadOnlyList<string> Count(IEnumerable<string> codes)
    {
        Dictionary<string, int> counts = new(StringComparer.Ordinal);
        foreach (string code in codes)
        {
            counts[code] = counts.TryGetValue(code, out int seen) ? seen + 1 : 1;
        }
        return [.. counts
            .OrderBy(entry => entry.Key, StringComparer.Ordinal)
            .Select(entry => $"{entry.Key}={entry.Value}")];
    }

    /// <summary>
    /// 지원 요청에 붙일 진단입니다. 카탈로그를 <b>디스크에서 다시 읽어</b> 무엇이 어긋났는지
    /// 코드별로 적습니다 — 실패 코드 하나로는 원인을 좁힐 수 없습니다.
    /// </summary>
    public Diagnostics.LibraryRecoveryDiagnostics BuildRecoveryDiagnostics(string appVersion)
    {
        StorageRootSet? roots = AttemptedRoots;
        return new Diagnostics.LibraryRecoveryDiagnostics(
            appVersion,
            State,
            SessionError,
            StoreError,
            DefectSidecarError,
            roots is null ? null : CatalogRecovery.PendingRestoreGenerationId(roots),
            BackupGenerations(),
            roots is null ? null : CatalogFileInspector.Inspect(roots.CatalogPath),
            UnreadableFrameCount,
            FrameIssueCodes(),
            FrameRepairCodes());
    }

    /// <summary>백업 세대 목록입니다. 새 것이 먼저 옵니다.</summary>
    public IReadOnlyList<CatalogBackupGeneration> BackupGenerations() =>
        AttemptedRoots is { } roots ? CatalogBackupInspector.Enumerate(roots) : [];

    /// <summary>
    /// 고른 세대로 되돌리도록 예약합니다. 실제 치환은 <b>다음 열기</b>에 일어납니다 —
    /// 지금 열려 있는 카탈로그를 발밑에서 갈아 끼우지 않습니다.
    /// </summary>
    public CatalogPendingRestoreScheduleResult ScheduleRestore(string generationId)
    {
        if (document is { } open)
        {
            return open.ScheduleRestore(generationId);
        }
        using CatalogSession? session = OpenTemporarySession();
        return session is null
            ? new CatalogPendingRestoreScheduleResult(
                null,
                default,
                CatalogPendingRestoreError.InvalidStorageRoots)
            : session.ScheduleRestore(generationId);
    }

    public CatalogPendingRestoreOperationResult CancelScheduledRestore()
    {
        if (document is { } open)
        {
            return open.CancelScheduledRestore();
        }
        using CatalogSession? session = OpenTemporarySession();
        return session is null
            ? new CatalogPendingRestoreOperationResult(
                CatalogPendingRestoreError.InvalidStorageRoots)
            : session.CancelScheduledRestore();
    }

    /// <summary>
    /// 마지막 탈출구입니다. 지금 카탈로그와 결함 기록을 옆에 보관하고 빈 카탈로그를
    /// <b>직접 세운 뒤</b> 다시 엽니다.
    /// </summary>
    /// <remarks>
    /// 그냥 지우기만 하면 유효하지 않은 백업 세대가 남아 있을 때 다시 차단 화면으로
    /// 돌아옵니다. 사진 원본과 백업 세대는 건드리지 않습니다 — 나중에 백업에서 되돌릴 수
    /// 있어야 합니다.
    /// </remarks>
    public bool StartFreshLibrary()
    {
        if (document is not null || AttemptedRoots is not { } roots)
        {
            return false;
        }
        return CatalogSidelinedFiles.PrepareFreshStart(roots) &&
            WriteEmptyCatalog(roots) &&
            Open(roots) == LibraryHostState.Open;
    }

    /// <summary>
    /// 다시 열어 봅니다. 복구 화면의 "다시 시도" 입니다. 이미 열려 있으면 그대로 둡니다.
    /// </summary>
    public LibraryHostState RetryOpen() =>
        document is not null || AttemptedRoots is not { } roots ? State : Open(roots);

    private static bool WriteEmptyCatalog(StorageRootSet roots)
    {
        using CatalogSession? session = CatalogSession.Open(roots).Session;
        return session is not null && session.Write(CatalogSnapshot.Empty).IsSuccess;
    }

    private CatalogSession? OpenTemporarySession() =>
        AttemptedRoots is { } roots ? CatalogSession.Open(roots).Session : null;
}
