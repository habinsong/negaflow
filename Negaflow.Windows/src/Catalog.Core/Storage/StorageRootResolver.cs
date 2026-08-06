namespace Negaflow.Catalog;

public static class StorageRootResolver
{
    private const string ProductFolderName = "Negaflow";

    public static StorageRootResolutionResult ResolveProduction()
    {
        string localApplicationData = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);
        return Resolve(localApplicationData, isTestIsolated: false);
    }

    public static StorageRootResolutionResult ResolveForTests(
        string isolatedLocalApplicationDataRoot) =>
        Resolve(isolatedLocalApplicationDataRoot, isTestIsolated: true);

    private static StorageRootResolutionResult Resolve(
        string baseRoot,
        bool isTestIsolated)
    {
        if (string.IsNullOrWhiteSpace(baseRoot))
        {
            return StorageRootResolutionResult.Failure(
                StorageRootResolutionError.MissingBaseRoot);
        }
        if (!Path.IsPathFullyQualified(baseRoot))
        {
            return StorageRootResolutionResult.Failure(
                StorageRootResolutionError.BaseRootNotFullyQualified);
        }

        string localApplicationDataRoot;
        try
        {
            localApplicationDataRoot = Path.TrimEndingDirectorySeparator(
                Path.GetFullPath(baseRoot));
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return StorageRootResolutionResult.Failure(
                StorageRootResolutionError.InvalidBaseRoot);
        }

        string productDataRoot = Path.Combine(
            localApplicationDataRoot,
            ProductFolderName);
        string libraryRoot = Path.Combine(productDataRoot, "Library");

        return StorageRootResolutionResult.Success(new StorageRootSet(
            localApplicationDataRoot,
            productDataRoot,
            libraryRoot,
            Path.Combine(libraryRoot, "library.sqlite"),
            Path.Combine(libraryRoot, "library.backup.sqlite"),
            Path.Combine(libraryRoot, "library.sqlite.lock"),
            Path.Combine(libraryRoot, "defects"),
            Path.Combine(libraryRoot, "Backups"),
            Path.Combine(libraryRoot, "PendingRestore"),
            Path.Combine(libraryRoot, "Migration"),
            Path.Combine(productDataRoot, "Cache"),
            Path.Combine(productDataRoot, "Journals"),
            Path.Combine(productDataRoot, "Plugins"),
            Path.Combine(productDataRoot, "Logs"),
            Path.Combine(productDataRoot, "Settings"),
            isTestIsolated));
    }
}
