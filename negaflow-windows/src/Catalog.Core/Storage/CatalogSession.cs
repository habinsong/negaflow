namespace Negaflow.Catalog;

public enum CatalogSessionError
{
    None,

    /// <summary>storage root 가 계약을 벗어났습니다.</summary>
    InvalidStorageRoots,

    /// <summary>다른 프로세스가 이미 이 카탈로그의 작성자입니다.</summary>
    Busy,

    ReparsePointNotAllowed,
    AccessDenied,
    IoFailure,
    PendingRestoreFailed,
    MissingAuthoritativeData,
}

public readonly record struct CatalogSessionOpenResult(
    CatalogSession? Session,
    CatalogSessionError Error)
{
    public CatalogPendingRestoreError PendingRestoreError { get; init; }

    public int ObservedVersion { get; init; }

    public DefectSidecarError DefectSidecarError { get; init; }

    public bool IsSuccess => Error == CatalogSessionError.None && Session is not null;

    internal static CatalogSessionOpenResult Success(CatalogSession session) =>
        new(session, CatalogSessionError.None);

    internal static CatalogSessionOpenResult Failure(
        CatalogSessionError error,
        CatalogPendingRestoreError pendingRestoreError =
            CatalogPendingRestoreError.None,
        int observedVersion = 0,
        DefectSidecarError defectSidecarError = DefectSidecarError.None) =>
        new(null, error)
        {
            PendingRestoreError = pendingRestoreError,
            ObservedVersion = observedVersion,
            DefectSidecarError = defectSidecarError,
        };
}

/// <summary>
/// 카탈로그를 읽고 쓰는 **유일한** 공개 입구입니다. 프로세스 lock 을 잡지 않고는 세션을 만들 수
/// 없으므로 단일 작성자 계약을 호출자의 규율이 아니라 구조가 강제합니다.
/// </summary>
/// <remarks>
/// 세션은 SQLite 연결을 계속 붙들고 있지 않습니다. 연산마다 열고 닫으므로 backup 세대 교체와
/// pending restore 가 파일을 치환할 수 있습니다. lock 파일은 세션이 살아 있는 동안 유지됩니다.
/// </remarks>
public sealed class CatalogSession : IDisposable
{
    private readonly StorageRootSet roots;
    private readonly object writeGate = new();
    private CatalogProcessLock? processLock;
    private bool mutationBlocked;

    private CatalogSession(
        StorageRootSet roots,
        CatalogProcessLock processLock,
        CatalogPendingRestoreApplicationResult pendingRestoreApplication)
    {
        this.roots = roots;
        this.processLock = processLock;
        PendingRestoreApplication = pendingRestoreApplication;
    }

    public bool IsOpen => Volatile.Read(ref processLock) is not null;

    public string CatalogPath => roots.CatalogPath;

    public CatalogPendingRestoreApplicationResult PendingRestoreApplication { get; }

    public static CatalogSessionOpenResult Open(StorageRootSet roots) =>
        OpenCore(roots, cleanup: null);

    internal static CatalogSessionOpenResult OpenForTesting(
        StorageRootSet roots,
        CatalogPendingRestoreCleanup cleanup) =>
        OpenCore(roots, cleanup);

    private static CatalogSessionOpenResult OpenCore(
        StorageRootSet roots,
        CatalogPendingRestoreCleanup? cleanup)
    {
        ArgumentNullException.ThrowIfNull(roots);

        CatalogProcessLockAcquireResult acquired = CatalogProcessLock.TryAcquire(roots);
        if (acquired.Lock is not { } held)
        {
            return CatalogSessionOpenResult.Failure(Translate(acquired.Error));
        }

        CatalogPendingRestoreApplicationResult pending = cleanup is { } injected
            ? CatalogPendingRestoreStore.ApplyIfScheduled(
                roots,
                DateTimeOffset.UtcNow,
                injected)
            : CatalogPendingRestoreStore.ApplyIfScheduled(
                roots,
                DateTimeOffset.UtcNow);
        if (!pending.IsSuccess)
        {
            held.Dispose();
            return CatalogSessionOpenResult.Failure(
                CatalogSessionError.PendingRestoreFailed,
                pending.Error,
                pending.ObservedVersion);
        }

        CatalogReadResult catalog = SqliteCatalogStore.Read(roots.CatalogPath);
        if (catalog.Snapshot is { } snapshot)
        {
            DefectCatalogHealthResult health =
                DefectSidecarStore.ValidateCatalogDeclarations(roots, snapshot);
            if (!health.IsHealthy)
            {
                held.Dispose();
                return CatalogSessionOpenResult.Failure(
                    CatalogSessionError.MissingAuthoritativeData,
                    defectSidecarError: health.Error);
            }
        }
        else if (catalog.Error == CatalogStoreError.NotFound &&
            DefectSidecarStore.HasAnyArtifact(roots))
        {
            held.Dispose();
            return CatalogSessionOpenResult.Failure(
                CatalogSessionError.MissingAuthoritativeData,
                defectSidecarError: DefectSidecarError.InvalidContent);
        }
        return CatalogSessionOpenResult.Success(
            new CatalogSession(roots, held, pending));
    }

    public CatalogReadResult Read()
    {
        lock (writeGate)
        {
            RequireOpen();
            return SqliteCatalogStore.Read(roots.CatalogPath);
        }
    }

    public CatalogWriteResult Write(CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }
            if (!DefectSidecarStore.ValidateCatalogDeclarations(roots, snapshot).IsHealthy)
            {
                return CatalogWriteResult.Failure(
                    CatalogStoreError.MissingAuthoritativeData);
            }
            return ObserveCommitResult(CatalogCommitVerifier.Commit(snapshot, roots));
        }
    }

    public DefectSidecarReadResult ReadDefectRecipe(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return DefectSidecarStore.Read(roots, frameId);
        }
    }

    /// <summary>
    /// sidecar를 먼저 durable하게 기록합니다. 호출자는 이 성공 뒤 catalog의
    /// hasDefectEdits를 true로 commit해야 하며, 반대 순서는 Write가 거부합니다.
    /// </summary>
    public DefectSidecarWriteResult WriteDefectRecipe(
        DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectSidecarWriteResult.Failure(
                    DefectSidecarError.IoFailure);
            }
            return DefectSidecarStore.Write(roots, snapshot);
        }
    }

    /// <summary>
    /// catalog가 더는 해당 frame의 edit을 선언하지 않을 때만 sidecar를 지웁니다.
    /// catalog false commit → sidecar remove 순서라 crash 시 orphan만 남고 recipe 유실은 없습니다.
    /// </summary>
    public DefectSidecarDeleteResult RemoveDefectRecipe(
        Guid frameId,
        ulong minimumRevision)
    {
        lock (writeGate)
        {
            RequireOpen();
            CatalogReadResult current = SqliteCatalogStore.Read(roots.CatalogPath);
            if (current.Snapshot is not { } snapshot ||
                CatalogDeclaresDefectEdits(snapshot, frameId))
            {
                return DefectSidecarDeleteResult.Failure(
                    DefectSidecarError.InvalidSnapshot);
            }
            return DefectSidecarStore.Remove(roots, frameId, minimumRevision);
        }
    }

    public CatalogBackupCreateResult CreateBackup(
        int retentionCount = CatalogBackupStore.DefaultRetentionCount)
    {
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked ||
                CatalogCommitVerifier.HasUnresolvedRollbackArtifact(roots))
            {
                mutationBlocked = true;
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.RecoveryRequired);
            }
            return CatalogBackupStore.Create(
                roots,
                DateTimeOffset.UtcNow,
                retentionCount);
        }
    }

    public CatalogPendingRestoreScheduleResult ScheduleRestore(
        string generationId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return CatalogPendingRestoreStore.Schedule(
                roots,
                generationId,
                DateTimeOffset.UtcNow);
        }
    }

    public CatalogPendingRestoreOperationResult CancelScheduledRestore()
    {
        lock (writeGate)
        {
            RequireOpen();
            return CatalogPendingRestoreStore.Cancel(roots);
        }
    }

    internal CatalogPendingRestoreScheduleResult ScheduleRestoreForTesting(
        string generationId,
        DateTimeOffset scheduledAt)
    {
        lock (writeGate)
        {
            RequireOpen();
            return CatalogPendingRestoreStore.Schedule(
                roots,
                generationId,
                scheduledAt);
        }
    }

    internal CatalogBackupCreateResult CreateBackupForTesting(
        DateTimeOffset createdAt,
        int retentionCount = CatalogBackupStore.DefaultRetentionCount,
        Action<string>? beforeValidation = null)
    {
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked ||
                CatalogCommitVerifier.HasUnresolvedRollbackArtifact(roots))
            {
                mutationBlocked = true;
                return CatalogBackupCreateResult.Failure(
                    CatalogBackupError.RecoveryRequired);
            }
            return CatalogBackupStore.Create(
                roots,
                createdAt,
                retentionCount,
                beforeValidation);
        }
    }

    internal CatalogWriteResult WriteForTesting(
        CatalogSnapshot snapshot,
        Func<CatalogSnapshot, string, CatalogWriteResult>? writer = null,
        Func<string, CatalogReadResult>? readback = null,
        Func<CatalogPrimarySnapshot, StorageRootSet, bool>? restore = null)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }
            return ObserveCommitResult(CatalogCommitVerifier.CommitForTesting(
                snapshot,
                roots,
                writer,
                readback,
                restore));
        }
    }

    /// <summary>
    /// 없는 카탈로그를 처음 여는 정상 경로입니다. <see cref="CatalogStoreError.NotFound"/> 를
    /// 빈 라이브러리로 바꾸는 것은 여기 한 곳에서만 일어나며, 그 자리에서 파일을 만듭니다.
    /// 손상이나 알 수 없는 version 은 그대로 실패로 남습니다.
    /// </summary>
    public CatalogReadResult ReadOrCreate()
    {
        lock (writeGate)
        {
            RequireOpen();
            if (CatalogCommitVerifier.HasUnresolvedRollbackArtifact(roots))
            {
                mutationBlocked = true;
                return CatalogReadResult.Failure(CatalogStoreError.RollbackFailed);
            }

            CatalogReadResult read = SqliteCatalogStore.Read(roots.CatalogPath);
            if (read.Error != CatalogStoreError.NotFound)
            {
                return read;
            }
            if (mutationBlocked)
            {
                return CatalogReadResult.Failure(CatalogStoreError.RollbackFailed);
            }
            if (CatalogCommitVerifier.HasBlockingArtifactWhenPrimaryMissing(roots))
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.MissingAuthoritativeData);
            }
            if (DefectSidecarStore.HasAnyArtifact(roots))
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.MissingAuthoritativeData);
            }

            CatalogWriteResult created = ObserveCommitResult(
                CatalogCommitVerifier.Commit(CatalogSnapshot.Empty, roots));
            return created.IsSuccess
                ? SqliteCatalogStore.Read(roots.CatalogPath)
                : CatalogReadResult.Failure(created.Error);
        }
    }

    public void Dispose()
    {
        lock (writeGate)
        {
            Interlocked.Exchange(ref processLock, null)?.Dispose();
        }
    }

    private CatalogWriteResult ObserveCommitResult(CatalogWriteResult result)
    {
        if (result.Error == CatalogStoreError.RollbackFailed)
        {
            mutationBlocked = true;
        }
        return result;
    }

    private void RequireOpen()
    {
        ObjectDisposedException.ThrowIf(!IsOpen, this);
    }

    private static bool CatalogDeclaresDefectEdits(
        CatalogSnapshot snapshot,
        Guid frameId)
    {
        string expected = frameId.ToString("D");
        foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
        {
            if (!string.Equals(frame.Id, expected, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            return frame.Payload.TryGetPropertyValue(
                    "hasDefectEdits",
                    out System.Text.Json.Nodes.JsonNode? node) &&
                node is System.Text.Json.Nodes.JsonValue value &&
                value.TryGetValue(out bool hasEdits) &&
                hasEdits;
        }
        return false;
    }

    private static CatalogSessionError Translate(CatalogProcessLockError error) => error switch
    {
        CatalogProcessLockError.InvalidStorageRoots => CatalogSessionError.InvalidStorageRoots,
        CatalogProcessLockError.ReparsePointNotAllowed =>
            CatalogSessionError.ReparsePointNotAllowed,
        CatalogProcessLockError.Busy => CatalogSessionError.Busy,
        CatalogProcessLockError.AccessDenied => CatalogSessionError.AccessDenied,
        _ => CatalogSessionError.IoFailure,
    };
}
