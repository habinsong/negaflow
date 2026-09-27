namespace Negaflow.Catalog;

/// <summary>
/// 복구 판단에 필요한 값싼 확인과, 카탈로그를 열 수 없을 때의 복원 예약만 공개합니다. 여기서는
/// catalog 를 열지도 payload 를 읽지도 않습니다. 실제 읽기와 쓰기는 <see cref="CatalogSession"/>
/// 을 통해서만 할 수 있습니다.
/// </summary>
public static class CatalogRecovery
{
    /// <summary>
    /// 손상된 primary 가 유효한 backup 을 덮지 않게 하는 확인입니다. 전체 payload 를 디코드하지
    /// 않고 <c>integrity_check</c> 와 물리·논리 두 version 축만 봅니다.
    /// </summary>
    public static bool IsValidCatalogSource(string catalogPath) =>
        SqliteCatalogStore.IsValidRecoverySource(catalogPath);

    /// <summary>
    /// 다음 열기에 되돌릴 세대가 예약돼 있으면 그 id 입니다. 없으면 <c>null</c> 입니다 —
    /// 복구 화면이 "다음 실행에 복원됩니다" 를 보여 줄지 판단합니다.
    /// </summary>
    public static string? PendingRestoreGenerationId(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        return CatalogPendingRestoreFiles.TryReadMarker(
            roots,
            out CatalogPendingRestoreMarker marker)
            ? marker.SourceGenerationId
            : null;
    }

    /// <summary>
    /// 카탈로그를 열 수 없을 때(복구 화면) 백업 세대 복원을 예약합니다. macOS
    /// <c>LibraryPendingRestoreStore.schedule</c> 처럼 카탈로그를 열지 않고 예약만 적습니다 —
    /// 세션을 열면 막힌 까닭(선언된 결함 기록이 없음 등)에 다시 걸려 예약조차 못 했습니다.
    /// 다른 프로세스와 겹치지 않게 프로세스 lock 만 잡습니다.
    /// </summary>
    public static CatalogPendingRestoreScheduleResult ScheduleRestore(
        StorageRootSet roots,
        string generationId)
    {
        ArgumentNullException.ThrowIfNull(roots);
        CatalogProcessLockAcquireResult acquired = CatalogProcessLock.TryAcquire(roots);
        if (acquired.Lock is not { } held)
        {
            return CatalogPendingRestoreScheduleResult.Failure(LockFailure(acquired.Error));
        }
        using (held)
        {
            return CatalogPendingRestoreStore.Schedule(roots, generationId, DateTimeOffset.UtcNow);
        }
    }

    /// <summary>macOS <c>LibraryPendingRestoreStore.cancel</c> — 예약과 같은 까닭으로 열지 않습니다.</summary>
    public static CatalogPendingRestoreOperationResult CancelScheduledRestore(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        CatalogProcessLockAcquireResult acquired = CatalogProcessLock.TryAcquire(roots);
        if (acquired.Lock is not { } held)
        {
            return CatalogPendingRestoreOperationResult.Failure(LockFailure(acquired.Error));
        }
        using (held)
        {
            return CatalogPendingRestoreStore.Cancel(roots);
        }
    }

    private static CatalogPendingRestoreError LockFailure(CatalogProcessLockError error) =>
        error switch
        {
            CatalogProcessLockError.AccessDenied => CatalogPendingRestoreError.AccessDenied,
            CatalogProcessLockError.InvalidStorageRoots or
                CatalogProcessLockError.ReparsePointNotAllowed =>
                CatalogPendingRestoreError.InvalidStorageRoots,
            _ => CatalogPendingRestoreError.IoFailure,
        };
}
