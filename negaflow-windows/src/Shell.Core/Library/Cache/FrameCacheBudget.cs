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

    private const double NativePreviewBytesPerPixel = 16.0;

    private const double ManagedDisplayBytesPerPixel = 4.0;

    private static double DevelopedBudgetFraction =>
        (DevelopedPerCleanedRaw * DevelopedMegabytesPerFrame) / UnitMegabytes;

    private static double ManagedDisplayFraction =>
        ManagedDisplayBytesPerPixel /
        (NativePreviewBytesPerPixel + ManagedDisplayBytesPerPixel);

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

    /// <summary>
    /// Windows의 managed BGRA8 정착본이 쓸 바이트 상한입니다. macOS의 developed 170MiB에는
    /// raw 프록시와 최종 표시 이미지가 함께 포함되므로, Windows의 native Rgba32F(16B/px)와
    /// managed BGRA8(4B/px)이 같은 developed 몫을 실제 화소 바이트 비율로 나눕니다.
    /// </summary>
    public static long AutomaticDevelopedDisplayBudgetBytes(ulong physicalMemoryBytes)
    {
        double totalMegabytes = physicalMemoryBytes <= ConservativeMemoryCeilingBytes
            ? (MinimumCleanedRaw * CleanedRawMegabytesPerFrame) +
                (MinimumDeveloped * DevelopedMegabytesPerFrame)
            : Megabytes(physicalMemoryBytes) * AutomaticMemoryFraction(physicalMemoryBytes);
        double displayMegabytes =
            totalMegabytes * DevelopedBudgetFraction * ManagedDisplayFraction;
        double bytes = displayMegabytes * 1024.0 * 1024.0;
        return bytes >= long.MaxValue ? long.MaxValue : Math.Max(1L, (long)bytes);
    }

    /// <summary>
    /// 수동 모드 상한입니다. macOS <c>manualMaximumLimits(physicalMemoryBytes:)</c>
    /// (<c>FrameCacheBudget.swift:70-81</c>) 그대로입니다.
    /// </summary>
    /// <remarks>
    /// 자동값보다 낮은 상한은 뜻이 없습니다 — 자동에서 수동으로 옮길 때 값이 잘립니다.
    /// 그래서 예산으로 구한 값과 자동값 중 큰 쪽을 씁니다.
    /// </remarks>
    public static FrameCacheLimits ManualMaximumLimits(ulong physicalMemoryBytes)
    {
        FrameCacheLimits budgeted = LimitsForBudget(
            Megabytes(physicalMemoryBytes) * ManualMemoryFraction);
        FrameCacheLimits automatic = AutomaticLimits(physicalMemoryBytes);
        return new FrameCacheLimits(
            Math.Max(budgeted.CleanedRaw, automatic.CleanedRaw),
            Math.Max(budgeted.Developed, automatic.Developed));
    }

    /// <summary>macOS <c>residentMemoryFraction(_:physicalMemoryBytes:)</c>.</summary>
    public static double ResidentMemoryFraction(
        FrameCacheLimits limits,
        ulong physicalMemoryBytes)
    {
        double total = Megabytes(physicalMemoryBytes);
        return total > 0 ? EstimatedResidentMegabytes(limits) / total : 0;
    }

    /// <summary>
    /// 주어진 한도에 맞는 managed BGRA8 표시본 예산입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="AutomaticDevelopedDisplayBudgetBytes"/> 와 같은 환산인데, 자동 한도가 아니라
    /// **지금 적용되는 한도**를 받습니다. 수동 모드에서 한도를 올렸는데 표시본 예산만 자동값에
    /// 묶여 있으면 늘린 만큼 안 담깁니다.
    /// </remarks>
    public static long DevelopedDisplayBudgetBytes(FrameCacheLimits limits)
    {
        double developedMegabytes = limits.Developed * DevelopedMegabytesPerFrame;
        double displayMegabytes = developedMegabytes * ManagedDisplayFraction;
        double bytes = displayMegabytes * 1024.0 * 1024.0;
        return bytes >= long.MaxValue ? long.MaxValue : Math.Max(1L, (long)bytes);
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
