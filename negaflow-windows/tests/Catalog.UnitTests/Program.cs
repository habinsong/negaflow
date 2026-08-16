using System.Text.Json;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == CatalogProcessLockTests.LockContenderArgument)
        {
            return CatalogStorageTests.RunLockContender(args[1]);
        }

        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        DevelopRouteTests.Run(fixture.RootElement);
        DevelopRecipeCatalogTests.Run();
        LibraryFrameTests.RunAppMetadataPersistence();
        CatalogStorageTests.Run();
        LibraryFrameTests.RunFrameBehavior();

        var report = new
        {
            status = CatalogTestAssert.Failures.Count == 0 ? "ok" : "failed",
            operation = "catalog_unit_tests",
            assertions = CatalogTestAssert.AssertionCount,
            failures = CatalogTestAssert.Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return CatalogTestAssert.Failures.Count == 0 ? 0 : 1;
    }
}
