using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

internal static class TestAssert
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

    public static bool Near(double actual, double expected) =>
        Math.Abs(actual - expected) <= 1e-9;

    public static bool NearRect(
        CropDisplayRect actual,
        double x,
        double y,
        double width,
        double height) =>
        Near(actual.X, x) && Near(actual.Y, y) &&
        Near(actual.Width, width) && Near(actual.Height, height);
}
