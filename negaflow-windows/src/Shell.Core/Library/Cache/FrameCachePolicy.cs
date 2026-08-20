namespace Negaflow.Shell.Library;

/// <summary>
/// macOS <c>Services/Cache/FrameCachePolicy.swift</c> 이식본입니다.
/// </summary>
/// <remarks>
/// Windows 에는 <c>DispatchSource.MemoryPressureEvent</c> 대응이 아직 없으므로
/// 지금 쓰이는 것은 <see cref="FrameCachePressureLevel.Normal"/> 뿐입니다. 나머지 두
/// 단계는 macOS 값을 그대로 담아 두었고, 압력 감시가 붙으면 그때 연결합니다 —
/// <c>docs/audit/10-cache-and-optimization.md</c> 1.2절.
/// </remarks>
public enum FrameCachePressureLevel
{
    Normal,
    Warning,
    Critical,
}

/// <summary>macOS <c>FrameCacheLimits</c>.</summary>
public readonly record struct FrameCacheLimits
{
    public FrameCacheLimits(int cleanedRaw, int developed)
    {
        // Swift init: max(0, cleanedRaw) / max(1, developed)
        CleanedRaw = Math.Max(0, cleanedRaw);
        Developed = Math.Max(1, developed);
    }

    public int CleanedRaw { get; }

    public int Developed { get; }
}

/// <summary>macOS <c>FrameCachePolicy</c>.</summary>
public readonly record struct FrameCachePolicy
{
    public FrameCachePolicy()
        : this(new FrameCacheLimits(cleanedRaw: 2, developed: 3))
    {
    }

    public FrameCachePolicy(FrameCacheLimits normalLimits) => NormalLimits = normalLimits;

    public FrameCacheLimits NormalLimits { get; }

    public FrameCacheLimits LimitsFor(FrameCachePressureLevel pressure) => pressure switch
    {
        FrameCachePressureLevel.Normal => NormalLimits,
        FrameCachePressureLevel.Warning => new FrameCacheLimits(
            Math.Min(NormalLimits.CleanedRaw, 1),
            Math.Min(NormalLimits.Developed, 2)),
        _ => new FrameCacheLimits(cleanedRaw: 0, developed: 1),
    };
}
