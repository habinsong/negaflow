using Negaflow.Interop;

namespace Negaflow.Shell.Library;

/// <summary><see cref="FrameCacheResidencyMode"/> 와 같은 갈래입니다.</summary>
public enum GpuCacheMode
{
    Automatic,
    Manual,
}

/// <summary>
/// GPU 작업 텍스처 캐시 한도 설정(자동/수동)입니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>macOS 에는 이 자리가 없습니다.</b> 통합 메모리라 GPU 텍스처가 이미 RAM 캐시 예산 안에
/// 들어 있기 때문입니다. Windows 는 외장 그래픽에서 아예 다른 물리 메모리(VRAM)를 쓰므로,
/// RAM 예산이 아무리 정확해도 GPU 쪽은 한 줄도 안 세어집니다. 48MP 한 장이 float32 RGBA 로
/// 770MB 이고 <c>GpuImagePool</c> 이 최대 여섯 장 + 보존 여섯 장이라, 막지 않으면 한 풀이
/// 9.2GB 를 잡습니다.
/// </para>
/// <para>
/// 값을 정하는 셈은 <b>엔진이</b> 합니다(<c>GpuCacheBudget</c>) — 어댑터가 내장인지, DXGI 가
/// 이 프로세스에 지금 얼마를 주는지는 엔진만 압니다. 여기는 "자동인가 수동인가, 수동이면
/// 몇 MB 인가" 만 들고 있습니다.
/// </para>
/// </remarks>
public sealed record GpuCacheSettings
{
    /// <summary>
    /// 슬라이더 한 눈금입니다. <b>예산 하한이 아닙니다</b> — 기계마다 VRAM 도 RAM 도 다르므로
    /// 바이트 상수를 예산으로 박지 않습니다. 상·하한은 모두 이 기계가 보고한 용량에서 옵니다
    /// (<see cref="MinimumMegabytesFor"/> · <see cref="MaximumMegabytesFor"/>).
    /// </summary>
    public const int StepMegabytes = 256;

    public GpuCacheMode Mode { get; init; } = GpuCacheMode.Automatic;

    /// <summary>
    /// 수동 모드에서 쓸 값(MB)입니다. 0 이면 "저장된 값 없음" 이고, 그때는 자동값에서
    /// 시작합니다 — <see cref="FrameCacheResidencySettings.ManualCleanedRaw"/> 와 같은 규칙입니다.
    /// </summary>
    public int ManualMegabytes { get; init; }

    /// <summary>
    /// 엔진에 걸 바이트입니다. 자동이면 0 — 엔진이 어댑터를 보고 직접 잡습니다.
    /// </summary>
    public long LimitBytesToApply() =>
        Mode == GpuCacheMode.Manual && ManualMegabytes > 0
            ? (long)ManualMegabytes * 1024L * 1024L
            : 0L;

    /// <summary>
    /// 수동 슬라이더의 상한입니다. 외장은 DXGI 가 준 예산(없으면 전용 VRAM), 내장은 설치
    /// RAM 의 1/4 입니다 — 내장에서 VRAM 은 시스템 RAM 이라 RAM 캐시와 같은 물리 메모리를
    /// 두고 다툽니다.
    /// </summary>
    public static int MaximumMegabytesFor(GpuCacheInfo info, ulong installedMemoryBytes)
    {
        ulong ceiling = info.IsIntegrated
            ? installedMemoryBytes / 4UL
            : (info.VideoMemoryBudgetBytes > 0UL
                ? info.VideoMemoryBudgetBytes
                : info.DedicatedVideoMemoryBytes);
        long megabytes = (long)(ceiling / (1024UL * 1024UL));
        return (int)Math.Max(MinimumMegabytesFor(info, installedMemoryBytes), megabytes);
    }

    /// <summary>
    /// 수동 슬라이더의 하한입니다. 상한의 1/16 이며 눈금 하나보다는 큽니다 — 기계가 크면
    /// 하한도 같이 커집니다.
    /// </summary>
    public static int MinimumMegabytesFor(GpuCacheInfo info, ulong installedMemoryBytes)
    {
        ulong ceiling = info.IsIntegrated
            ? installedMemoryBytes / 4UL
            : (info.VideoMemoryBudgetBytes > 0UL
                ? info.VideoMemoryBudgetBytes
                : info.DedicatedVideoMemoryBytes);
        long sixteenth = (long)(ceiling / (16UL * 1024UL * 1024UL));
        return (int)Math.Max(StepMegabytes, sixteenth - (sixteenth % StepMegabytes));
    }

    /// <summary>지금 자동값을 MB 로 읽습니다. 화면이 "자동: 4.8 GB" 를 낼 자리입니다.</summary>
    public static int AutomaticMegabytes(GpuCacheInfo info) =>
        (int)(info.AutomaticLimitBytes / (1024UL * 1024UL));

    /// <summary>수동값을 지금 자동값으로 되돌립니다.</summary>
    public GpuCacheSettings ResetManualToAutomatic(GpuCacheInfo info) =>
        this with { ManualMegabytes = AutomaticMegabytes(info) };

    /// <remarks>
    /// 여기서는 기계 용량을 모르므로 <b>음수만</b> 걸러 냅니다. 실제 상·하한은 설정 화면이
    /// 이 기계의 <see cref="GpuCacheInfo"/> 로 잡습니다 — 저장된 값을 기계 모르는 상수로
    /// 자르면 GPU 를 바꾼 뒤 값이 조용히 깎입니다.
    /// </remarks>
    public GpuCacheSettings Normalize() => this with
    {
        Mode = Enum.IsDefined(Mode) ? Mode : GpuCacheMode.Automatic,
        ManualMegabytes = Math.Max(0, ManualMegabytes),
    };
}
