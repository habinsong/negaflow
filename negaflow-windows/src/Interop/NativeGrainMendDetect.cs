using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>GrainMend 자동·가이드 검출 진입점입니다.</summary>
internal static partial class NativeGrainMendDetect
{
    private const string LibraryName = NativeMethods.LibraryName;

    // 자동·가이드 GrainMend 는 수리 결과가 아니라 판정을 받아 갑니다. 검출은 film look 뒤,
    // 현상된 양화 위에서 돌아야 macOS 와 같은 것을 찾습니다.
    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v1(
        NativeDevelopExportRequestV27* request,
        byte* mask,
        ulong maskCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV1* detection,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v2(
        NativeDevelopExportRequestV27* request,
        NativeGrainMendDetectParametersV1* parameters,
        byte* mask,
        ulong maskCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV2* detection,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v3")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v3(
        NativeDevelopExportRequestV27* request,
        NativeGrainMendDetectParametersV2* parameters,
        byte* mask,
        ulong maskCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV2* detection,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v4")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v4(
        NativeDevelopExportRequestV27* request,
        NativeGrainMendDetectParametersV3* parameters,
        byte* mask,
        ulong maskCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV2* detection,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v5")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v5(
        NativeDevelopExportRequestV27* request,
        NativeGrainMendDetectParametersV3* parameters,
        byte* mask,
        ulong maskCapacityBytes,
        NativeGrainMendComponentV1* components,
        ulong componentCapacity,
        NativeGrainMendPreviewPointV1* previewPoints,
        ulong previewPointCapacity,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV3* detection,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_detect_grain_mend_v6")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_detect_grain_mend_v6(
        NativeDevelopExportRequestV27* request,
        NativeGrainMendDetectParametersV3* parameters,
        byte* mask,
        ulong maskCapacityBytes,
        NativeGrainMendComponentV1* components,
        ulong componentCapacity,
        NativeGrainMendPreviewPointV1* previewPoints,
        ulong previewPointCapacity,
        NativeDevelopRunStateV1* runState,
        NativeGrainMendDetectionV4* detection,
        NativeDevelopExportResultV3* result);
}
