namespace Negaflow.Interop;

internal static unsafe class NativeAbiReader
{
    internal const int BuildInfoV1Size = 44;
    internal const int SourceCommitSha1Offset = 24;
    internal const ushort SupportedMajor = 0;

    // Raised with each export the managed side calls: 2 for nf_develop_export_v1,
    // 4 for nf_get_negative_limits_v1, 5 for nf_develop_preview_v1.
    // 3 for nf_get_tone_limits_v1, 6 for the base-mode v2 preview/export calls,
    // 9 for Basic Tone v3 preview/export, 10 for Film base v4 preview/export,
    // 11 for Point Curve v5 preview/export, 12 for Color Mixer v6 preview/export,
    // 13 for Color Grading v7 preview/export, 14 for GrainMend v8, 15 for
    // FilmScanDenoise v9, 16 for Texture v10, 17 for B&W toning plus
    // ImageTransform v11, 18 for variable Local Dodge/Burn v12, 19 for
    // ColorModel v13, 20 for scene correction v14, 21 for DevelopTarget v15,
      // 22 for scanner profile ID v16, 23 for film polarity v17, 24 for
      // ordered pre-develop Defects region edits v18, 25 for source identity
      // v19, 26 for ordered Clone Stamp v20, 27 for Brush v21, and 28 for the
      // caller-owned run state v22 that carries cancellation and progress, and 29
      // for automatic tone and white balance, 30 for preview soft proof, and 31
      // for replaying persisted infrared attenuation in preview and export, and 32
      // for preserving infrared item boundaries across those shared paths, and 33
      // for paired visible/IR detection with an owned variable-payload handle, and 34
      // for reading paired scanner TIFFs directly into that detector, and 35 for
      // flatbed frame-grid detection with an owned result handle, and 36 for
      // output sharpening after the final image transform, 37 for TIFF source metadata
      // preflight at import and relink, 38 for creative primary calibration, and 39 for
      // JPEG/PNG source preflight at import and relink, and 40 for JPEG output
      // quality plus DPI metadata, 41 for linear-light long-edge output scaling, and
      // 42 for GrainMend review detector tuning, 43 for its optional micro-speck pass,
      // 44 for TIFF compression plus PNG/TIFF DPI output metadata, and 45 for
      // eight-bit PNG/TIFF publication with output dither, 46 for output colour space, 47 for the export metadata policy,
      // and 48 for preserve-alpha export, 49 for transient background preview caching,
      // 50 for exact GrainMend review ownership, and 51 for explicit Defects append-prefix reuse.
    // An engine below this is refused at load, not at the call.
    internal const ushort MinimumMinor = 51;

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
