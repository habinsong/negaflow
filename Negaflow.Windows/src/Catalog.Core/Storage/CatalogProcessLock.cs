namespace Negaflow.Catalog;

public enum CatalogProcessLockError
{
    None,
    InvalidStorageRoots,
    ReparsePointNotAllowed,
    Busy,
    AccessDenied,
    IoFailure,
}

public readonly record struct CatalogProcessLockAcquireResult(
    CatalogProcessLock? Lock,
    CatalogProcessLockError Error)
{
    public bool IsSuccess => Error == CatalogProcessLockError.None && Lock is not null;

    internal static CatalogProcessLockAcquireResult Success(CatalogProcessLock processLock) =>
        new(processLock, CatalogProcessLockError.None);

    internal static CatalogProcessLockAcquireResult Failure(CatalogProcessLockError error) =>
        new(null, error);
}

public sealed class CatalogProcessLock : IDisposable
{
    private const int ErrorSharingViolation = 32;
    private FileStream? lockStream;

    private CatalogProcessLock(FileStream lockStream)
    {
        this.lockStream = lockStream;
    }

    public bool IsHeld => Volatile.Read(ref lockStream) is not null;

    public static CatalogProcessLockAcquireResult TryAcquire(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);

        if (!StoragePathPolicy.IsLexicallyContained(
                roots.ProductDataRoot,
                roots.LibraryRoot) ||
            !StoragePathPolicy.IsLexicallyContained(
                roots.LibraryRoot,
                roots.CatalogLockPath))
        {
            return CatalogProcessLockAcquireResult.Failure(
                CatalogProcessLockError.InvalidStorageRoots);
        }

        CatalogProcessLockError preparationError = PrepareLockParent(roots);
        if (preparationError != CatalogProcessLockError.None)
        {
            return CatalogProcessLockAcquireResult.Failure(preparationError);
        }

        try
        {
            FileStream stream = new(roots.CatalogLockPath, new FileStreamOptions
            {
                Mode = FileMode.OpenOrCreate,
                Access = FileAccess.ReadWrite,
                Share = FileShare.None,
                Options = FileOptions.None,
            });
            if (StoragePathPolicy.IsExistingReparsePoint(roots.CatalogLockPath))
            {
                stream.Dispose();
                return CatalogProcessLockAcquireResult.Failure(
                    CatalogProcessLockError.ReparsePointNotAllowed);
            }
            return CatalogProcessLockAcquireResult.Success(new CatalogProcessLock(stream));
        }
        catch (IOException error) when ((error.HResult & 0xffff) == ErrorSharingViolation)
        {
            return CatalogProcessLockAcquireResult.Failure(CatalogProcessLockError.Busy);
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogProcessLockAcquireResult.Failure(
                CatalogProcessLockError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return CatalogProcessLockAcquireResult.Failure(
                CatalogProcessLockError.IoFailure);
        }
    }

    public void Dispose()
    {
        Interlocked.Exchange(ref lockStream, null)?.Dispose();
    }

    private static CatalogProcessLockError PrepareLockParent(StorageRootSet roots)
    {
        try
        {
            Directory.CreateDirectory(roots.LibraryRoot);
            if (StoragePathPolicy.IsExistingReparsePoint(roots.ProductDataRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.LibraryRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.CatalogLockPath))
            {
                return CatalogProcessLockError.ReparsePointNotAllowed;
            }
            return CatalogProcessLockError.None;
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogProcessLockError.AccessDenied;
        }
        catch (Exception error) when (error is
            IOException or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return CatalogProcessLockError.IoFailure;
        }
    }
}
