using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>엔진 검증기가 강제하는 한계값입니다.</summary>
internal static partial class NativeLimits
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_get_negative_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_negative_limits_v1(ref NativeNegativeLimitsV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_tone_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_tone_limits_v1(ref NativeToneLimitsV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_set_frame_cache_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_set_frame_cache_limits_v1(
        ref NativeFrameCacheLimitsV1 limits);

    [LibraryImport(LibraryName, EntryPoint = "nf_set_gpu_cache_limit_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_set_gpu_cache_limit_v1(ref NativeGpuCacheLimitV1 limit);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_gpu_cache_info_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_gpu_cache_info_v1(ref NativeGpuCacheInfoV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_memory_report_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_memory_report_v1(ref NativeMemoryReportV1 output);
}
