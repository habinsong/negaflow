namespace Negaflow.Catalog;

public enum StorageRootResolutionError
{
    None,
    MissingBaseRoot,
    BaseRootNotFullyQualified,
    InvalidBaseRoot,
}

public readonly record struct StorageRootResolutionResult(
    StorageRootSet? Roots,
    StorageRootResolutionError Error)
{
    public bool IsSuccess => Error == StorageRootResolutionError.None && Roots is not null;

    internal static StorageRootResolutionResult Success(StorageRootSet roots) =>
        new(roots, StorageRootResolutionError.None);

    internal static StorageRootResolutionResult Failure(StorageRootResolutionError error) =>
        new(null, error);
}
