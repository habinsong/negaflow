using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>엔진 검증기가 강제하는 한계값입니다.</summary>
internal static partial class NativeLimits
{
    private const string LibraryName = NativeMethods.LibraryName;

    [LibraryImport(LibraryName, EntryPoint = "nf_get_negative_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_negative_limits_v1(ref NativeNegativeLimitsV1 output);

    [LibraryImport(LibraryName, EntryPoint = "nf_get_tone_limits_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    internal static partial uint nf_get_tone_limits_v1(ref NativeToneLimitsV1 output);
}
