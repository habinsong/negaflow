using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

internal static partial class NativeMethods
{
    internal const string LibraryName = "Negaflow.Native";
    internal const string FileName = "Negaflow.Native.dll";

    [LibraryImport(LibraryName, EntryPoint = "nf_get_abi_version")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_abi_version();

    [LibraryImport(LibraryName, EntryPoint = "nf_get_build_info_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_build_info_v1(ref NativeBuildInfoV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v1(
        NativeDevelopExportRequestV1* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV1* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v2(
        NativeDevelopExportRequestV2* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v3")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v3(
        NativeDevelopExportRequestV3* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v4")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v4(
        NativeDevelopExportRequestV4* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v5")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v5(
        NativeDevelopExportRequestV5* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v6")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v6(
        NativeDevelopExportRequestV6* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v7")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v7(
        NativeDevelopExportRequestV7* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v8")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v8(
        NativeDevelopExportRequestV8* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v9")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v9(
        NativeDevelopExportRequestV9* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v10")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v10(
        NativeDevelopExportRequestV10* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v11")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v11(
        NativeDevelopExportRequestV11* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v12")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v12(
        NativeDevelopExportRequestV12* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v13")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v13(
        NativeDevelopExportRequestV13* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v14")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v14(
        NativeDevelopExportRequestV14* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v15")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v15(
        NativeDevelopExportRequestV15* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v16")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v16(
        NativeDevelopExportRequestV16* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v17")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v17(
        NativeDevelopExportRequestV17* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v18")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v18(
        NativeDevelopExportRequestV18* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v19")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v19(
        NativeDevelopExportRequestV19* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v20")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v20(
        NativeDevelopExportRequestV20* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_preview_v21")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_preview_v21(
        NativeDevelopExportRequestV21* request,
        uint maximumWidth,
        uint maximumHeight,
        byte* pixels,
        uint pixelCapacityBytes,
        NativeDevelopExportResultV2* result);

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

    [LibraryImport(LibraryName, EntryPoint = "nf_auto_adjust_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_auto_adjust_v1(
        byte* pixels,
        uint width,
        uint height,
        uint strideBytes,
        NativeAutoAdjustResultV1* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_negative_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_negative_limits_v1(ref NativeNegativeLimitsV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_tone_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_tone_limits_v1(ref NativeToneLimitsV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v1(
        NativeDevelopExportRequestV1* request,
        NativeDevelopExportResultV1* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v2")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v2(
        NativeDevelopExportRequestV2* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v3")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v3(
        NativeDevelopExportRequestV3* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v4")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v4(
        NativeDevelopExportRequestV4* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v5")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v5(
        NativeDevelopExportRequestV5* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v6")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v6(
        NativeDevelopExportRequestV6* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v7")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v7(
        NativeDevelopExportRequestV7* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v8")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v8(
        NativeDevelopExportRequestV8* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v9")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v9(
        NativeDevelopExportRequestV9* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v10")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v10(
        NativeDevelopExportRequestV10* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v11")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v11(
        NativeDevelopExportRequestV11* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v12")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v12(
        NativeDevelopExportRequestV12* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v13")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v13(
        NativeDevelopExportRequestV13* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v14")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v14(
        NativeDevelopExportRequestV14* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v15")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v15(
        NativeDevelopExportRequestV15* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v16")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v16(
        NativeDevelopExportRequestV16* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v17")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v17(
        NativeDevelopExportRequestV17* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v18")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v18(
        NativeDevelopExportRequestV18* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v19")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v19(
        NativeDevelopExportRequestV19* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v20")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v20(
        NativeDevelopExportRequestV20* request,
        NativeDevelopExportResultV2* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_develop_export_v21")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_develop_export_v21(
        NativeDevelopExportRequestV21* request,
        NativeDevelopExportResultV2* result);
}
