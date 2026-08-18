using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>적외선 결함 검출과 그 핸들 수명입니다.</summary>
internal static partial class NativeInfraredDetect
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_detect_infrared_defects_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_detect_infrared_defects_v1(
        float* infrared,
        uint infraredStrideBytes,
        float* red,
        uint redStrideBytes,
        uint width,
        uint height,
        NativeInfraredDetectorParametersV1* parameters,
        uint* cancelRequested,
        NativeInfraredDetectionSummaryV1* summary,
        nint* handle);

    [LibraryImport(LibraryName, EntryPoint = "nf_detect_infrared_defects_from_tiff_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_detect_infrared_defects_from_tiff_v1(
        char* visiblePath,
        char* infraredPath,
        NativeInfraredDetectorParametersV1* parameters,
        uint* cancelRequested,
        NativeInfraredDetectionSummaryV1* summary,
        nint* handle);

    [LibraryImport(LibraryName, EntryPoint = "nf_infrared_detection_get_cluster_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_infrared_detection_get_cluster_v1(
        nint handle,
        ulong index,
        NativeInfraredClusterV1* cluster,
        byte* coreMask,
        ulong coreMaskCapacityBytes,
        ushort* attenuationR16,
        ulong attenuationCapacityValues);

    [LibraryImport(LibraryName, EntryPoint = "nf_infrared_detection_get_component_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_infrared_detection_get_component_v1(
        nint handle,
        ulong index,
        NativeInfraredComponentV1* component,
        NativeInfraredPreviewPointV1* previewPoints,
        ulong previewPointCapacity);

    [LibraryImport(LibraryName, EntryPoint = "nf_infrared_detection_destroy_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial void nf_infrared_detection_destroy_v1(nint handle);
}
