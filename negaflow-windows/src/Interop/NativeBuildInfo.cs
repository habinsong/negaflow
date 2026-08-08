namespace Negaflow.Interop;

public enum NativeArchitecture : uint
{
    Unknown = 0,
    X64 = 1,
    Arm64 = 2,
}

[Flags]
public enum NativeCpuFeatures : uint
{
    None = 0,
    AvxUsable = 1U << 0,
    Avx2 = 1U << 1,
    Fma = 1U << 2,
    NeonBaseline = 1U << 3,
}

public enum NativeCompiler : uint
{
    Unknown = 0,
    Msvc = 1,
}

public sealed record NativeBuildInfo(
    NativeAbiVersion AbiVersion,
    NativeArchitecture Architecture,
    NativeCpuFeatures CpuFeatures,
    NativeCompiler Compiler,
    uint CompilerVersion,
    string SourceCommitSha1);
