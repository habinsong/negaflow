using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>평판 프레임 격자 검출과 그 핸들 수명입니다.</summary>
internal static partial class NativeFlatbedDetect
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_detect_flatbed_frame_grid_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_detect_flatbed_frame_grid_v1(
        float* luminance,
        uint strideBytes,
        uint width,
        uint height,
        double physicalWidthMm,
        double physicalHeightMm,
        uint format,
        uint* cancelRequested,
        NativeFlatbedFrameGridSummaryV1* summary,
        nint* handle);

    [LibraryImport(LibraryName, EntryPoint = "nf_flatbed_frame_grid_get_detection_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_flatbed_frame_grid_get_detection_v1(
        nint handle,
        ulong index,
        NativeFlatbedFrameDetectionV1* detection);

    [LibraryImport(LibraryName, EntryPoint = "nf_flatbed_frame_grid_destroy_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial void nf_flatbed_frame_grid_destroy_v1(nint handle);
}
