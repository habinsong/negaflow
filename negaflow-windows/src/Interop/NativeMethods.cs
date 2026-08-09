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
}
