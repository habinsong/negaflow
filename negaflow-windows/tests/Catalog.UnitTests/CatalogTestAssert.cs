namespace Negaflow.Catalog.UnitTests;

internal static class CatalogTestAssert
{
    private static readonly List<string> failures = [];
    private static int assertionCount;

    public static IReadOnlyList<string> Failures => failures;

    public static int AssertionCount => assertionCount;

    public static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            failures.Add(name);
        }
    }
}
