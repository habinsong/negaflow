using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>가져오기·재연결이 경로를 바꾸기 전에 쓰는 원본 검사입니다.</summary>
internal static partial class NativeSourceProbe
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_probe_tiff_source_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_probe_tiff_source_v1(
        char* sourcePath,
        NativeTiffSourceInfoV1* result);

    [LibraryImport(LibraryName, EntryPoint = "nf_probe_standard_image_source_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_probe_standard_image_source_v1(
        char* sourcePath,
        NativeStandardImageSourceInfoV1* result);
}
