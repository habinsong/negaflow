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
}
