using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class CatalogStorageTests
{
    public static void Run()
    {
        StorageRootTests.Run();
        CatalogProcessLockTests.Run();

        string testParent = Path.Combine(AppContext.BaseDirectory, "catalog-store-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            SqliteCatalogStoreTests.Run(roots);
            DefectSidecarTests.Run(roots);
            DefectRecipeBatchTransactionTests.Run(roots);
            CatalogBackupRestoreTests.Run(roots);
            DefectCatalogRecoveryTests.Run(roots);
            CatalogSessionTests.Run(roots);
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    internal static int RunLockContender(string isolatedBase) =>
        CatalogProcessLockTests.RunLockContender(isolatedBase);
}
