using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>v1-v21 파일 내보내기 진입점입니다.</summary>
internal static partial class NativeDevelopExport
{
    private const string LibraryName = NativeMethods.LibraryName;

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
