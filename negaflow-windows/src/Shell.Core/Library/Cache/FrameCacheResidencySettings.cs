namespace Negaflow.Shell.Library;

/// <summary>macOS <c>FrameCacheResidencyStore.Mode</c>.</summary>
public enum FrameCacheResidencyMode
{
    Automatic,
    Manual,
}

/// <summary>
/// 상주 프레임 한도 설정(자동/수동)입니다. macOS
/// <c>Services/Cache/FrameCacheResidencyStore.swift</c> 이식본입니다.
/// </summary>
/// <remarks>
/// <para>
/// **캐시 동작 자체는 건드리지 않습니다.** 한도를 계산하는 <see cref="FrameCacheBudget"/>
/// 도, 축출을 하는 <c>FrameResidency</c> 도 그대로입니다. 여기가 하는 일은 "지금 적용할
/// 한도가 무엇인가" 하나뿐입니다 — 지금까지는 <c>ThumbnailService</c> 가 자동값을 바로
/// 불러 써서 **사용자가 바꿀 길이 없었습니다.**
/// </para>
/// <para>
/// macOS 는 이 값을 <c>UserDefaults</c> 에 둡니다. Windows 는 <c>ShellPreferences</c> 가
/// 같은 자리이므로 거기에 담습니다.
/// </para>
/// </remarks>
public sealed record FrameCacheResidencySettings
{
    public FrameCacheResidencyMode Mode { get; init; } = FrameCacheResidencyMode.Automatic;

    /// <summary>
    /// 수동 모드에서 쓸 값입니다. 0 이면 "저장된 값 없음" 이고, 그때는 자동값에서 시작합니다 —
    /// macOS 가 <c>defaults.object(forKey:) as? Int</c> 로 같은 판정을 합니다.
    /// </summary>
    public int ManualCleanedRaw { get; init; }

    public int ManualDeveloped { get; init; }

    /// <summary>이 기계의 설치 메모리로 자동 한도를 구합니다.</summary>
    public static FrameCacheLimits AutomaticLimits(ulong physicalMemoryBytes) =>
        FrameCacheBudget.AutomaticLimits(physicalMemoryBytes);

    public static FrameCacheLimits ManualMaximumLimits(ulong physicalMemoryBytes) =>
        FrameCacheBudget.ManualMaximumLimits(physicalMemoryBytes);

    /// <summary>지금 실제로 적용되는 한도입니다. macOS <c>effectiveLimits</c>.</summary>
    public FrameCacheLimits EffectiveLimits(ulong physicalMemoryBytes)
    {
        if (Mode == FrameCacheResidencyMode.Automatic)
        {
            return AutomaticLimits(physicalMemoryBytes);
        }
        FrameCacheLimits automatic = AutomaticLimits(physicalMemoryBytes);
        FrameCacheLimits maximum = ManualMaximumLimits(physicalMemoryBytes);
        int cleanedRaw = ManualCleanedRaw > 0 ? ManualCleanedRaw : automatic.CleanedRaw;
        int developed = ManualDeveloped > 0 ? ManualDeveloped : automatic.Developed;
        return new FrameCacheLimits(
            Math.Clamp(cleanedRaw, FrameCacheBudget.MinimumCleanedRaw, maximum.CleanedRaw),
            Math.Clamp(developed, FrameCacheBudget.MinimumDeveloped, maximum.Developed));
    }

    public double EstimatedResidentMegabytes(ulong physicalMemoryBytes) =>
        FrameCacheBudget.EstimatedResidentMegabytes(EffectiveLimits(physicalMemoryBytes));

    public double EstimatedResidentFraction(ulong physicalMemoryBytes) =>
        FrameCacheBudget.ResidentMemoryFraction(
            EffectiveLimits(physicalMemoryBytes), physicalMemoryBytes);

    /// <summary>수동 값을 지금 자동값으로 되돌립니다. macOS <c>resetManualToAutomatic()</c>.</summary>
    public FrameCacheResidencySettings ResetManualToAutomatic(ulong physicalMemoryBytes)
    {
        FrameCacheLimits automatic = AutomaticLimits(physicalMemoryBytes);
        return this with
        {
            ManualCleanedRaw = automatic.CleanedRaw,
            ManualDeveloped = automatic.Developed,
        };
    }

    public FrameCacheResidencySettings Normalize()
    {
        return this with
        {
            Mode = Enum.IsDefined(Mode) ? Mode : FrameCacheResidencyMode.Automatic,
            ManualCleanedRaw = ManualCleanedRaw <= 0
                ? 0
                : Math.Clamp(
                    ManualCleanedRaw,
                    FrameCacheBudget.MinimumCleanedRaw,
                    FrameCacheBudget.MaximumCleanedRaw),
            ManualDeveloped = ManualDeveloped <= 0
                ? 0
                : Math.Clamp(
                    ManualDeveloped,
                    FrameCacheBudget.MinimumDeveloped,
                    FrameCacheBudget.MaximumDeveloped),
        };
    }
}
