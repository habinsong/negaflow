using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class NativeBuildInfoContractTests
{
    internal static void Verify(ContractTestContext context, NativeBuildInfo buildInfo)
    {
        // Compatibility, not an exact pin. A minor ahead of the minimum is a valid
        // engine; pinning the exact number turned every added export into a test edit.
        // The exact version still reaches the report below.
        context.Check(
            buildInfo.AbiVersion.Major == NativeAbiReader.SupportedMajor &&
                buildInfo.AbiVersion.Minor >= NativeAbiReader.MinimumMinor,
            "abi_version");
        context.Check(buildInfo.Compiler == NativeCompiler.Msvc, "compiler");
        context.Check(buildInfo.CompilerVersion != 0, "compiler_version");
        context.Check(
            buildInfo.SourceCommitSha1.Length == 40 &&
                buildInfo.SourceCommitSha1.Any(character => character != '0'),
            "source_commit");

        NativeArchitecture expectedArchitecture = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => NativeArchitecture.X64,
            Architecture.Arm64 => NativeArchitecture.Arm64,
            _ => NativeArchitecture.Unknown,
        };
        context.Check(
            expectedArchitecture != NativeArchitecture.Unknown &&
                buildInfo.Architecture == expectedArchitecture,
            "architecture");

        bool avxUsable = buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.AvxUsable);
        context.Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Avx2) || avxUsable,
            "avx2_requires_avx_state");
        context.Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Fma) || avxUsable,
            "fma_requires_avx_state");
    }
}
