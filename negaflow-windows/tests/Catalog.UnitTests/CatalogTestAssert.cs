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

    /// <summary>
    /// 실패했을 때만 까닭을 덧붙입니다. "IsSuccess 가 false" 만 남는 실패는 다음 사람이
    /// 처음부터 다시 재현해야 합니다 — 오류 코드는 그 자리에서 남겨야 합니다.
    /// </summary>
    public static void Check(bool condition, string name, Func<string> detail)
    {
        ArgumentNullException.ThrowIfNull(detail);
        ++assertionCount;
        if (!condition)
        {
            failures.Add($"{name} ({detail()})");
        }
    }
}
