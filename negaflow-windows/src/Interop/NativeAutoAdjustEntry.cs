using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>자동 톤·화이트 밸런스 진입점입니다.</summary>
internal static partial class NativeAutoAdjustEntry
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_auto_adjust_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static unsafe partial uint nf_auto_adjust_v1(
        byte* pixels,
        uint width,
        uint height,
        uint strideBytes,
        NativeAutoAdjustResultV1* result);
}
