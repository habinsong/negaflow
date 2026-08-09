namespace Negaflow.Interop;

internal static unsafe class NativeAbiReader
{
    internal const int BuildInfoV1Size = 44;
    internal const int SourceCommitSha1Offset = 24;
    internal const ushort SupportedMajor = 0;

    // Raised with each export the managed side calls: 2 for nf_develop_export_v1,
    // 4 for nf_get_negative_limits_v1, 5 for nf_develop_preview_v1.
    // 3 for nf_get_tone_limits_v1, 6 for the base-mode v2 preview/export calls,
    // 9 for Basic Tone v3 preview/export, and 10 for Film base v4 preview/export.
    // An engine below this is refused at load, not at the call.
    internal const ushort MinimumMinor = 10;

    private const uint StatusOk = 0;

    internal static NativeBuildInfo Read()
    {
        if (sizeof(NativeBuildInfoV1) != BuildInfoV1Size)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The managed build-info layout does not match the C ABI.");
        }

        NativeAbiVersion exportedVersion =
            NativeAbiVersion.FromPacked(NativeMethods.nf_get_abi_version());
        ValidateVersion(exportedVersion);

        NativeBuildInfoV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeBuildInfoV1);

        uint status = NativeMethods.nf_get_build_info_v1(ref raw);
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_get_build_info_v1 failed with status {status}.");
        }

        NativeAbiVersion resultVersion = NativeAbiVersion.FromPacked(raw.AbiVersion);
        if (raw.StructSize != BuildInfoV1Size || resultVersion != exportedVersion)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native build-info layout or ABI version is inconsistent.");
        }

        NativeArchitecture architecture = (NativeArchitecture)raw.Architecture;
        NativeCompiler compiler = (NativeCompiler)raw.CompilerId;
        string sourceCommitSha1 = raw.GetSourceCommitSha1();

        if (!Enum.IsDefined(architecture) ||
            architecture == NativeArchitecture.Unknown ||
            !Enum.IsDefined(compiler) ||
            compiler == NativeCompiler.Unknown ||
            sourceCommitSha1.All(character => character == '0'))
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native build information is incomplete.");
        }

        return new NativeBuildInfo(
            resultVersion,
            architecture,
            (NativeCpuFeatures)raw.CpuFeatureFlags,
            compiler,
            raw.CompilerVersion,
            sourceCommitSha1);
    }

    private static void ValidateVersion(NativeAbiVersion version)
    {
        if (version.Major != SupportedMajor || version.Minor < MinimumMinor)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.AbiIncompatible,
                $"Native ABI {version} is incompatible with {SupportedMajor}.{MinimumMinor}.");
        }
    }
}
