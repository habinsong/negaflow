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
}

public readonly record struct CatalogSessionOpenResult(
    CatalogSession? Session,
    CatalogSessionError Error)
{
    public bool IsSuccess => Error == CatalogSessionError.None && Session is not null;

    internal static CatalogSessionOpenResult Success(CatalogSession session) =>
        new(session, CatalogSessionError.None);

    internal static CatalogSessionOpenResult Failure(CatalogSessionError error) =>
        new(null, error);
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
    private CatalogProcessLock? processLock;

    private CatalogSession(StorageRootSet roots, CatalogProcessLock processLock)
    {
        this.roots = roots;
        this.processLock = processLock;
    }

    public bool IsOpen => Volatile.Read(ref processLock) is not null;

    public string CatalogPath => roots.CatalogPath;

    public static CatalogSessionOpenResult Open(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);

        CatalogProcessLockAcquireResult acquired = CatalogProcessLock.TryAcquire(roots);
        if (acquired.Lock is not { } held)
        {
            return CatalogSessionOpenResult.Failure(Translate(acquired.Error));
        }
        return CatalogSessionOpenResult.Success(new CatalogSession(roots, held));
    }

    public CatalogReadResult Read()
    {
        RequireOpen();
        return SqliteCatalogStore.Read(roots.CatalogPath);
    }

    public CatalogWriteResult Write(CatalogSnapshot snapshot)
    {
        RequireOpen();
        return SqliteCatalogStore.Write(snapshot, roots.CatalogPath);
    }

    /// <summary>
    /// 없는 카탈로그를 처음 여는 정상 경로입니다. <see cref="CatalogStoreError.NotFound"/> 를
    /// 빈 라이브러리로 바꾸는 것은 여기 한 곳에서만 일어나며, 그 자리에서 파일을 만듭니다.
    /// 손상이나 알 수 없는 version 은 그대로 실패로 남습니다.
    /// </summary>
    public CatalogReadResult ReadOrCreate()
    {
        RequireOpen();

        CatalogReadResult read = SqliteCatalogStore.Read(roots.CatalogPath);
        if (read.Error != CatalogStoreError.NotFound)
        {
            return read;
        }

        CatalogWriteResult created = SqliteCatalogStore.Write(
            CatalogSnapshot.Empty,
            roots.CatalogPath);
        return created.IsSuccess
            ? SqliteCatalogStore.Read(roots.CatalogPath)
            : CatalogReadResult.Failure(created.Error);
    }

    public void Dispose()
    {
        Interlocked.Exchange(ref processLock, null)?.Dispose();
    }

    private void RequireOpen()
    {
        ObjectDisposedException.ThrowIf(!IsOpen, this);
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
