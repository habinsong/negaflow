using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class StorageRootTests
{
    public static void Run() => VerifyStorageRootResolution();

    private static void VerifyStorageRootResolution()
    {
        StorageRootResolutionResult missing = StorageRootResolver.ResolveForTests(string.Empty);
        Check(missing.Error == StorageRootResolutionError.MissingBaseRoot,
            "storage_root_rejects_empty");
        Check(missing.Roots is null, "storage_root_empty_no_partial_result");

        StorageRootResolutionResult relative = StorageRootResolver.ResolveForTests("relative");
        Check(relative.Error == StorageRootResolutionError.BaseRootNotFullyQualified,
            "storage_root_rejects_relative");

        string isolatedBase = Path.Combine(
            AppContext.BaseDirectory,
            "storage-root-tests",
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(isolatedBase);
        Check(resolution.IsSuccess, "storage_root_test_resolution_success");
        if (resolution.Roots is not { } roots)
        {
            return;
        }

        string expectedProductRoot = Path.Combine(
            Path.GetFullPath(isolatedBase),
            "Negaflow");
        Check(roots.IsTestIsolated, "storage_root_marks_test_isolation");
        Check(roots.ProductDataRoot == expectedProductRoot, "storage_root_product_path");
        Check(roots.LibraryRoot == Path.Combine(expectedProductRoot, "Library"),
            "storage_root_library_path");
        Check(roots.CatalogPath == Path.Combine(roots.LibraryRoot, "library.sqlite"),
            "storage_root_catalog_path");
        Check(roots.CatalogBackupPath ==
            Path.Combine(roots.LibraryRoot, "library.backup.sqlite"),
            "storage_root_catalog_backup_path");
        Check(roots.CatalogLockPath ==
            Path.Combine(roots.LibraryRoot, "library.sqlite.lock"),
            "storage_root_catalog_lock_path");
        Check(roots.DefectRecipeRoot == Path.Combine(roots.LibraryRoot, "defects"),
            "storage_root_defects_path");
        Check(roots.BackupRoot == Path.Combine(roots.LibraryRoot, "Backups"),
            "storage_root_backups_path");
        Check(roots.PendingRestoreRoot == Path.Combine(roots.LibraryRoot, "PendingRestore"),
            "storage_root_pending_restore_path");
        Check(roots.MigrationRoot == Path.Combine(roots.LibraryRoot, "Migration"),
            "storage_root_migration_path");
        Check(roots.CacheRoot == Path.Combine(expectedProductRoot, "Cache"),
            "storage_root_cache_path");
        Check(roots.JournalRoot == Path.Combine(expectedProductRoot, "Journals"),
            "storage_root_journal_path");
        Check(roots.PluginRoot == Path.Combine(expectedProductRoot, "Plugins"),
            "storage_root_plugin_path");
        Check(roots.LogRoot == Path.Combine(expectedProductRoot, "Logs"),
            "storage_root_log_path");
        Check(roots.SettingsRoot == Path.Combine(expectedProductRoot, "Settings"),
            "storage_root_settings_path");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.CatalogPath), "storage_path_catalog_contained");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.ProductDataRoot), "storage_path_root_contains_itself");
        Check(!StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            $"{roots.ProductDataRoot}-outside"), "storage_path_rejects_prefix_sibling");

        Check(StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", "library.sqlite"),
            out string resolvedCatalog), "storage_path_resolves_relative");
        Check(resolvedCatalog == roots.CatalogPath, "storage_path_relative_value");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("..", "outside"),
            out _), "storage_path_rejects_parent_escape");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            roots.CatalogPath,
            out _), "storage_path_rejects_rooted_input");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", ".", "library.sqlite"),
            out _), "storage_path_rejects_dot_component");
    }

}
