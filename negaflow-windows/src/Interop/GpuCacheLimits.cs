using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeGpuCacheLimitV1
{
    internal uint StructSize;
    internal uint Reserved;
    internal ulong LimitBytes;
}

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeGpuCacheInfoV1
{
    internal uint StructSize;
    internal uint HasGpu;
    internal uint IsIntegrated;
    internal uint Reserved;
    internal fixed byte AdapterDescription[160];
    internal ulong DedicatedVideoMemoryBytes;
    internal ulong VideoMemoryBudgetBytes;
    internal ulong AutomaticLimitBytes;
    internal ulong EffectiveLimitBytes;
    internal ulong ResidentBytes;
}

/// <summary>설정 창이 GPU 캐시 줄을 그리는 데 필요한 값입니다.</summary>
/// <param name="HasGpu">쓸 수 있는 GPU 가 있는지입니다. 없으면 설정 창은 그 줄을 내지 않습니다.</param>
/// <param name="IsIntegrated">내장 그래픽인지입니다 — VRAM 이 시스템 RAM 과 같은 물리 메모리입니다.</param>
/// <param name="AdapterDescription">DXGI 가 준 어댑터 이름입니다. 표시용입니다.</param>
/// <param name="DedicatedVideoMemoryBytes">어댑터가 보고한 전용 VRAM 입니다. 내장은 0 입니다.</param>
/// <param name="VideoMemoryBudgetBytes">DXGI 가 지금 이 프로세스에 준 예산입니다. 못 읽으면 0 입니다.</param>
/// <param name="AutomaticLimitBytes">자동 모드에서 걸리는 상한입니다.</param>
/// <param name="EffectiveLimitBytes">지금 실제로 걸려 있는 상한입니다.</param>
/// <param name="ResidentBytes">작업 텍스처가 지금 실제로 쓰고 있는 바이트입니다.</param>
public readonly record struct GpuCacheInfo(
    bool HasGpu,
    bool IsIntegrated,
    string AdapterDescription,
    ulong DedicatedVideoMemoryBytes,
    ulong VideoMemoryBudgetBytes,
    ulong AutomaticLimitBytes,
    ulong EffectiveLimitBytes,
    ulong ResidentBytes);

/// <summary>
/// 설정 창 "메모리 캐시" 의 GPU 항목을 엔진의 작업 텍스처 풀에 겁니다.
/// </summary>
/// <remarks>
/// <para>
/// RAM 쪽 <see cref="FrameCacheLimitsBridge"/> 와 나란한 자리입니다. RAM 예산은 디코드 원본과
/// 프리뷰 프록시만 세고, <b>GPU 텍스처는 어느 예산에도 들어 있지 않았습니다</b> — 48MP 한 장이
/// float32 RGBA 로 770MB 이고 풀이 최대 여섯 장이라 한 풀이 4.6GB 를 잡습니다.
/// </para>
/// <para>
/// macOS 에는 이 자리가 없습니다. 통합 메모리라 GPU 텍스처가 이미 RAM 예산 안이기 때문입니다.
/// Windows 는 외장 그래픽에서 아예 다른 물리 메모리를 쓰므로 따로 재야 합니다.
/// </para>
/// </remarks>
public static class GpuCacheBridge
{
    /// <summary>상한을 겁니다. 0 이면 엔진이 자동으로 잡습니다.</summary>
    public static unsafe bool Apply(long limitBytes)
    {
        NativeGpuCacheLimitV1 raw = new()
        {
            StructSize = (uint)sizeof(NativeGpuCacheLimitV1),
            LimitBytes = (ulong)Math.Max(0L, limitBytes),
        };
        try
        {
            return NativeLimits.nf_set_gpu_cache_limit_v1(ref raw) == 0;
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }

    /// <summary>지금 GPU 상황을 읽습니다. 엔진을 못 부르면 <see langword="null"/> 입니다.</summary>
    public static unsafe GpuCacheInfo? TryRead()
    {
        NativeGpuCacheInfoV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeGpuCacheInfoV1);
        try
        {
            if (NativeLimits.nf_get_gpu_cache_info_v1(ref raw) != 0)
            {
                return null;
            }
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }

        // `fixed byte[160]` 는 구조체가 지역 변수라 이미 고정돼 있습니다 — 다시 fixed 로
        // 묶으면 CS0213 입니다. 배열 자체가 주소이므로 그대로 읽습니다.
        byte* text = raw.AdapterDescription;
        int length = 0;
        while (length < 160 && text[length] != 0)
        {
            ++length;
        }
        string description = System.Text.Encoding.UTF8.GetString(text, length);
        return new GpuCacheInfo(
            raw.HasGpu != 0U,
            raw.IsIntegrated != 0U,
            description,
            raw.DedicatedVideoMemoryBytes,
            raw.VideoMemoryBudgetBytes,
            raw.AutomaticLimitBytes,
            raw.EffectiveLimitBytes,
            raw.ResidentBytes);
    }
}
