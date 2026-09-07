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

        VerifyIncompatibleEnginesAreRefused(context);
    }

    /// <summary>
    /// **예전 엔진은 적재 자체가 막혀야 합니다**(W45).
    /// </summary>
    /// <remarks>
    /// 위의 <c>abi_version</c> 은 <b>지금 실린</b> 엔진이 호환인지만 봅니다. 그것만으로는
    /// 판정이 느슨해졌을 때를 못 잡습니다 — 그러면 QA payload 에 남은 예전 DLL 이 그대로
    /// 실려 입력 감마·베이스 배율을 <b>조용히 무시</b>하고, 사용자에게는 슬라이더를 움직여도
    /// 그림이 안 바뀌는 것으로만 보입니다. 어디에도 오류가 남지 않습니다.
    ///
    /// 그래서 경계를 직접 잽니다. 입력 감마가 들어온 판이 0.<see cref="NativeAbiReader.MinimumMinor"/>
    /// 이므로 그 아래는 전부 거부여야 하고, 위는 받아야 합니다(export 가 늘어난 것뿐이라
    /// 정확히 못 박으면 export 하나 늘 때마다 시험을 고쳐야 합니다).
    /// </remarks>
    private static void VerifyIncompatibleEnginesAreRefused(ContractTestContext context)
    {
        ushort major = NativeAbiReader.SupportedMajor;
        ushort minimum = NativeAbiReader.MinimumMinor;

        context.Check(
            NativeAbiReader.IsCompatible(new NativeAbiVersion(major, minimum)),
            "abi_minimum_is_accepted");
        context.Check(
            NativeAbiReader.IsCompatible(new NativeAbiVersion(major, (ushort)(minimum + 1))),
            "abi_newer_minor_is_accepted");

        // 입력 감마 이전 판들. 하나라도 통과하면 그 엔진이 감마를 무시한 채 실립니다.
        for (ushort minor = 0; minor < minimum; ++minor)
        {
            context.Check(
                !NativeAbiReader.IsCompatible(new NativeAbiVersion(major, minor)),
                $"abi_refuses_older_minor_{minor}");
        }

        // 다른 major 는 방향과 무관하게 거부입니다 - 뜻이 달라진 ABI 입니다.
        context.Check(
            !NativeAbiReader.IsCompatible(new NativeAbiVersion((ushort)(major + 1), minimum)),
            "abi_refuses_newer_major");
        if (major > 0)
        {
            context.Check(
                !NativeAbiReader.IsCompatible(new NativeAbiVersion((ushort)(major - 1), ushort.MaxValue)),
                "abi_refuses_older_major");
        }
    }
}
