namespace Negaflow.Shell.UnitTests;

internal sealed record GrainMendLatencySummary(
    int Count,
    double MinimumMilliseconds,
    double MedianMilliseconds,
    double P95Milliseconds,
    double MaximumMilliseconds);

internal static class GrainMendPerformanceStatistics
{
    public static GrainMendLatencySummary Summarize(IEnumerable<double> values)
    {
        double[] ordered = [.. values.Order()];
        if (ordered.Length == 0)
        {
            return new GrainMendLatencySummary(0, 0.0, 0.0, 0.0, 0.0);
        }

        return new GrainMendLatencySummary(
            ordered.Length,
            Round(ordered[0]),
            Round(Percentile(ordered, 0.50)),
            Round(Percentile(ordered, 0.95)),
            Round(ordered[^1]));
    }

    private static double Percentile(double[] ordered, double fraction)
    {
        int rank = (int)Math.Ceiling(fraction * ordered.Length);
        return ordered[Math.Clamp(rank - 1, 0, ordered.Length - 1)];
    }

    private static double Round(double value) => Math.Round(value, 1);
}
