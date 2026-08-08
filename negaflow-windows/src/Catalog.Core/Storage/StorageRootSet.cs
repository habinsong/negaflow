namespace Negaflow.Catalog;

public sealed class StorageRootSet
{
    internal StorageRootSet(
        string localApplicationDataRoot,
        string productDataRoot,
        string libraryRoot,
        string catalogPath,
        string catalogBackupPath,
        string catalogLockPath,
        string defectRecipeRoot,
        string backupRoot,
        string pendingRestoreRoot,
        string migrationRoot,
        string cacheRoot,
        string journalRoot,
        string pluginRoot,
        string logRoot,
        string settingsRoot,
        bool isTestIsolated)
    {
        LocalApplicationDataRoot = localApplicationDataRoot;
        ProductDataRoot = productDataRoot;
        LibraryRoot = libraryRoot;
        CatalogPath = catalogPath;
        CatalogBackupPath = catalogBackupPath;
        CatalogLockPath = catalogLockPath;
        DefectRecipeRoot = defectRecipeRoot;
        BackupRoot = backupRoot;
        PendingRestoreRoot = pendingRestoreRoot;
        MigrationRoot = migrationRoot;
        CacheRoot = cacheRoot;
        JournalRoot = journalRoot;
        PluginRoot = pluginRoot;
        LogRoot = logRoot;
        SettingsRoot = settingsRoot;
        IsTestIsolated = isTestIsolated;
    }

    public string LocalApplicationDataRoot { get; }

    public string ProductDataRoot { get; }

    public string LibraryRoot { get; }

    public string CatalogPath { get; }

    public string CatalogBackupPath { get; }

    public string CatalogLockPath { get; }

    public string DefectRecipeRoot { get; }

    public string BackupRoot { get; }

    public string PendingRestoreRoot { get; }

    public string MigrationRoot { get; }

    public string CacheRoot { get; }

    public string JournalRoot { get; }

    public string PluginRoot { get; }

    public string LogRoot { get; }

    public string SettingsRoot { get; }

    public bool IsTestIsolated { get; }
}
