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
        string thumbnailRoot,
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
        ThumbnailRoot = thumbnailRoot;
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

    /// <summary>
    /// 라이브러리·필름스트립 썸네일의 디스크 백킹입니다. 캐시이므로 통째로 지워도 원본에서
    /// 다시 만들어집니다 — 여기에는 카탈로그도 원본도 두지 않습니다.
    /// </summary>
    public string ThumbnailRoot { get; }

    public string JournalRoot { get; }

    public string PluginRoot { get; }

    public string LogRoot { get; }

    public string SettingsRoot { get; }

    public bool IsTestIsolated { get; }
}
