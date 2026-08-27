using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>실행 상태(취소·진행)를 받는 v22 이후 내보내기·미리보기 진입점입니다.</summary>
internal static partial class NativeDevelopRun
{
    private const string LibraryName = NativeMethods.LibraryName;

    // v22 keeps the v21 request — the recipe did not change — and adds the caller-owned
    // run state plus the v3 result that answers cancellation as a field.
    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v22")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v22(
        NativeDevelopExportRequestV21* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v22")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v22(
        NativeDevelopExportRequestV21* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    // v23 is v22 plus a soft proof the caller may pass as null. There is no matching
    // export entry point: a published file must never carry a viewing simulation.
    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v23")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v23(
        NativeDevelopExportRequestV21* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v24")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v24(
        NativeDevelopExportRequestV24* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v24")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v24(
        NativeDevelopExportRequestV24* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v25")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v25(
        NativeDevelopExportRequestV25* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v25")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v25(
        NativeDevelopExportRequestV25* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v26")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v26(
        NativeDevelopExportRequestV26* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v26")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v26(
        NativeDevelopExportRequestV26* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v27")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v27(
        NativeDevelopExportRequestV27* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v27")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v27(
        NativeDevelopExportRequestV27* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v28")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v28(
        NativeDevelopExportRequestV28* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v28")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v28(
        NativeDevelopExportRequestV28* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v29")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v29(
        NativeDevelopExportRequestV29* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v29")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v29(
        NativeDevelopExportRequestV29* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v30")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v30(
        NativeDevelopExportRequestV30* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v30")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v30(
        NativeDevelopExportRequestV30* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v31")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v31(
        NativeDevelopExportRequestV31* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v31")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v31(
        NativeDevelopExportRequestV31* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v32")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v32(
        NativeDevelopExportRequestV32* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v33")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v33(
        NativeDevelopExportRequestV33* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v33")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v33(
        NativeDevelopExportRequestV33* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v34")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v34(
        NativeDevelopExportRequestV34* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v34")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v34(
        NativeDevelopExportRequestV34* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v35")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v35(
        NativeDevelopExportRequestV35* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v37")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v37(
        NativeDevelopExportRequestV37* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_bake_defects_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_bake_defects_v1(
        NativeDevelopExportRequestV35* request,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v35")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v35(
        NativeDevelopExportRequestV35* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v36")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v36(
        NativeDevelopExportRequestV36* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_background_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_background_v1(
        NativeDevelopExportRequestV35* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v32")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v32(
        NativeDevelopExportRequestV32* request,
        NativeSoftProofV1* softProof,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopRunStateV1* runState,
        NativeDevelopExportResultV3* result);
}
