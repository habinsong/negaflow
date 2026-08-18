using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>
/// 네이티브 라이브러리의 이름과, 어느 빌드가 실려 있는지를 묻는 진입점입니다. 도메인별
/// 진입점은 <c>NativeDevelopPreview</c> 처럼 각자의 타입이 소유합니다.
/// </summary>
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
