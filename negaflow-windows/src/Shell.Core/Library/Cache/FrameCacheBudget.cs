namespace Negaflow.Shell.Library;

/// <summary>
/// macOS <c>Services/Cache/FrameCacheBudget.swift</c> 이식본 — 상주 프레임 수 ↔ 메모리 예산.
/// </summary>
/// <remarks>
/// macOS 주석 원문(FrameCacheBudget.swift:5-7): 한도는 "미리 잡아 두는 양"이 아니라
/// <b>상한</b>이다. 실제로 방문한 프레임만 버퍼를 갖고, 한도를 넘으면 오래된 것부터 내려놓는다.
/// </remarks>
public static class FrameCacheBudget
{
    /// <summary>프레임당 상주 추정치(MB). macOS FrameCacheBudget.swift:9-13.</summary>
    public const double CleanedRawMegabytesPerFrame = 190.0;

    public const double DevelopedMegabytesPerFrame = 170.0;

    public const double AutomaticMinimumFraction = 0.25;

    public const double AutomaticMaximumFraction = 0.35;

    private const double AutomaticFractionReferenceGigabytes = 16.0;

    private const double AutomaticFractionStepGigabytes = 16.0;

    private const double AutomaticFractionStep = 0.025;

    public const double ManualMemoryFraction = 0.70;

    public const int MinimumCleanedRaw = 2;

    public const int MinimumDeveloped = 3;

    public const int MaximumCleanedRaw = 64;

    public const int MaximumDeveloped = 128;

    /// <summary>developed 는 cleaned raw 보다 자주 오가므로 자동 배분에서 두 배를 줍니다.</summary>
    public const int DevelopedPerCleanedRaw = 2;

    public const ulong ConservativeMemoryCeilingBytes = 8UL * 1024UL * 1024UL * 1024UL;

    private static double UnitMegabytes =>
        CleanedRawMegabytesPerFrame + (DevelopedPerCleanedRaw * DevelopedMegabytesPerFrame);

    public static double Megabytes(ulong bytes) => bytes / (1024.0 * 1024.0);

    /// <summary>macOS <c>automaticMemoryFraction(physicalMemoryBytes:)</c>.</summary>
    public static double AutomaticMemoryFraction(ulong physicalMemoryBytes)
    {
        double gigabytes = physicalMemoryBytes / (1024.0 * 1024.0 * 1024.0);
        double steps =
            (gigabytes - AutomaticFractionReferenceGigabytes) / AutomaticFractionStepGigabytes;
        return Math.Min(
            AutomaticMaximumFraction,
            Math.Max(
                AutomaticMinimumFraction,
                AutomaticMinimumFraction + (steps * AutomaticFractionStep)));
    }

    /// <summary>macOS <c>automaticLimits(physicalMemoryBytes:)</c>.</summary>
    public static FrameCacheLimits AutomaticLimits(ulong physicalMemoryBytes)
    {
        if (physicalMemoryBytes <= ConservativeMemoryCeilingBytes)
        {
            return new FrameCacheLimits(MinimumCleanedRaw, MinimumDeveloped);
        }
        return LimitsForBudget(
            Megabytes(physicalMemoryBytes) * AutomaticMemoryFraction(physicalMemoryBytes));
    }

    /// <summary>macOS <c>estimatedResidentMegabytes(_:)</c>.</summary>
    public static double EstimatedResidentMegabytes(FrameCacheLimits limits) =>
        (limits.CleanedRaw * CleanedRawMegabytesPerFrame) +
        (limits.Developed * DevelopedMegabytesPerFrame);

    private static FrameCacheLimits LimitsForBudget(double budgetMegabytes)
    {
        int units = Math.Max(1, (int)Math.Floor(budgetMegabytes / UnitMegabytes));
        return new FrameCacheLimits(
            Math.Min(MaximumCleanedRaw, Math.Max(MinimumCleanedRaw, units)),
            Math.Min(
                MaximumDeveloped,
                Math.Max(MinimumDeveloped, units * DevelopedPerCleanedRaw)));
    }
}
