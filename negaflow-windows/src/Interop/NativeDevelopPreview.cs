using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>v1-v21 미리보기 진입점입니다. 실행 상태 없이 블로킹으로 돕니다.</summary>
internal static partial class NativeDevelopPreview
{
    private const string LibraryName = NativeMethods.LibraryName;

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
}
