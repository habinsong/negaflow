using System.Text.Json;
using Negaflow.Catalog;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == CatalogProcessLockTests.LockContenderArgument)
        {
            return CatalogStorageTests.RunLockContender(args[1]);
        }
        if (args is ["--defect-transaction-only"])
        {
            RunDefectTransactionOnly();
            return Report("catalog_defect_transaction_tests");
        }
        if (args is ["--defect-sidecar-only"])
        {
            RunDefectSidecarOnly();
            return Report("catalog_defect_sidecar_tests");
        }

        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        DevelopRouteTests.Run(fixture.RootElement);
        DevelopRecipeCatalogTests.Run();
        LibraryFrameTests.RunAppMetadataPersistence();
        CatalogStorageTests.Run();
        LibraryFrameTests.RunFrameBehavior();
        DefectReviewTrackingTests.Run();
        LibraryDevelopHistoryTests.Run();

        return Report("catalog_unit_tests");
    }

    private static void RunDefectTransactionOnly()
        => RunIsolatedDefectTests(roots =>
        {
            DefectReviewTrackingTests.Run();
            DefectSidecarTests.RunTransaction(roots);
            DefectRecipeBatchTransactionTests.Run(roots);
        });

    private static void RunDefectSidecarOnly()
        => RunIsolatedDefectTests(DefectSidecarTests.Run);

    private static void RunIsolatedDefectTests(Action<StorageRootSet> run)
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            run(roots);
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

    private static int Report(string operation)
    {
        var report = new
        {
            status = CatalogTestAssert.Failures.Count == 0 ? "ok" : "failed",
            operation,
            assertions = CatalogTestAssert.AssertionCount,
            failures = CatalogTestAssert.Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return CatalogTestAssert.Failures.Count == 0 ? 0 : 1;
    }
}
