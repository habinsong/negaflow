using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativeBuildInfoV1
{
    internal uint StructSize;
    internal uint AbiVersion;
    internal uint Architecture;
    internal uint CpuFeatureFlags;
    internal uint CompilerId;
    internal uint CompilerVersion;
    internal fixed byte SourceCommitSha1[20];

    internal string GetSourceCommitSha1()
    {
        fixed (byte* source = SourceCommitSha1)
        {
            return Convert.ToHexString(new ReadOnlySpan<byte>(source, 20)).ToLowerInvariant();
        }
    }
}
