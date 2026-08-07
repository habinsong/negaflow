using System.Runtime.InteropServices;
using System.Text.Json;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class ContractTestRunner
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    internal static int Run(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("Usage: Negaflow.Interop.ContractTests <absolute-native-dll-path>");
            return 2;
        }

        VerifyManagedLayout();
        VerifyPathPolicy();

        NativeBuildInfo? buildInfo = null;
        try
        {
            buildInfo = NativeEngineBootstrap.LoadAndQuery(args[0]);
            VerifyBuildInfo(buildInfo);
            Check(
                NativeEngineBootstrap.LoadAndQuery(args[0]) == buildInfo,
                "same_path_reload_is_idempotent");
            VerifyDevelopExportContract();
        }
        catch (Exception exception)
        {
            Failures.Add($"bootstrap:{exception.GetType().Name}");
        }

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "interop_contract",
            assertions = assertionCount,
            failures = Failures,
            abi_version = buildInfo?.AbiVersion.ToString(),
            architecture = buildInfo?.Architecture.ToString().ToLowerInvariant(),
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyManagedLayout()
    {
        Check(sizeof(NativeBuildInfoV1) == NativeAbiReader.BuildInfoV1Size, "build_info_size");
        Check(
            Marshal.OffsetOf<NativeBuildInfoV1>(nameof(NativeBuildInfoV1.SourceCommitSha1)).ToInt32() ==
                NativeAbiReader.SourceCommitSha1Offset,
            "source_commit_offset");

        // The native side static_asserts the same three numbers. Both halves have to
        // be checked, because a layout drift binds cleanly and then reads garbage.
        Check(
            sizeof(NativeDevelopExportRequestV1) == NativeDevelopExporter.RequestV1Size,
            "develop_export_request_size");
        Check(
            sizeof(NativeDevelopExportResultV1) == NativeDevelopExporter.ResultV1Size,
            "develop_export_result_size");
        Check(
            Marshal.OffsetOf<NativeDevelopExportRequestV1>(
                nameof(NativeDevelopExportRequestV1.FilmEmulationIntensity)).ToInt32() == 80,
            "develop_export_intensity_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.FailureName)).ToInt32() == 12,
            "develop_export_failure_name_offset");
        Check(
            Marshal.OffsetOf<NativeDevelopExportResultV1>(
                nameof(NativeDevelopExportResultV1.SourceFileBytes)).ToInt32() == 104,
            "develop_export_source_bytes_offset");
    }

    private static void VerifyDevelopExportContract()
    {
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-develop-export-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        // A missing source must be reported as an observation failure, not as a
        // malformed request, so the shell can tell a user error from a bug.
        DevelopExportResult missing = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
        });
        Check(!missing.Succeeded, "develop_export_missing_source_fails");
        Check(
            missing.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "develop_export_missing_source_stage");
        Check(missing.FailureName.Length > 0, "develop_export_failure_name_present");
        Check(missing.FailureName != "ok", "develop_export_failure_name_not_ok");
        Check(!File.Exists(destination), "develop_export_failure_writes_nothing");

        // The rendered-digital graph is not implemented and must refuse rather than
        // develop a negative through it anyway.
        DevelopExportResult digital = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = destination,
            FilmLookSourceKind = DevelopSourceKind.RenderedDigital,
        });
        Check(!digital.Succeeded, "develop_export_digital_source_fails");
        Check(
            digital.FailedStage == DevelopExportStage.RequestValidation,
            "develop_export_digital_source_stage");
        Check(
            digital.FailureName == "negative_develop_requires_film_scan_source",
            "develop_export_digital_source_name");

        CheckThrows<ArgumentException>(
            () => NativeDevelopExporter.Run(new DevelopExportRequest
            {
                SourcePath = absentSource,
                DestinationPath = destination,
                FilmEmulation = (FilmEmulationProfile)99,
            }),
            "develop_export_undefined_enum_rejected");

        CheckThrows<ArgumentNullException>(
            () => NativeDevelopExporter.Run(null!),
            "develop_export_null_request_rejected");
    }

    private static void VerifyPathPolicy()
    {
        CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(NativeMethods.FileName),
            "relative_path_rejected");

        string wrongName = Path.Combine(Path.GetTempPath(), "not-negaflow-native.dll");
        CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(wrongName),
            "wrong_file_name_rejected");

        string missingLibrary = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-missing-{Guid.NewGuid():N}",
            NativeMethods.FileName);
        ++assertionCount;
        try
        {
            NativeEngineBootstrap.LoadAndQuery(missingLibrary);
            Failures.Add("missing_library_classified");
        }
        catch (NativeBootstrapException exception)
            when (exception.Failure == NativeBootstrapFailure.LoadFailed)
        {
        }
    }

    private static void VerifyBuildInfo(NativeBuildInfo buildInfo)
    {
        // Compatibility, not an exact pin. A minor ahead of the minimum is a valid
        // engine; pinning the exact number turned every added export into a test edit.
        // The exact version still reaches the report below.
        Check(
            buildInfo.AbiVersion.Major == NativeAbiReader.SupportedMajor &&
                buildInfo.AbiVersion.Minor >= NativeAbiReader.MinimumMinor,
            "abi_version");
        Check(buildInfo.Compiler == NativeCompiler.Msvc, "compiler");
        Check(buildInfo.CompilerVersion != 0, "compiler_version");
        Check(
            buildInfo.SourceCommitSha1.Length == 40 &&
                buildInfo.SourceCommitSha1.Any(character => character != '0'),
            "source_commit");

        NativeArchitecture expectedArchitecture = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => NativeArchitecture.X64,
            Architecture.Arm64 => NativeArchitecture.Arm64,
            _ => NativeArchitecture.Unknown,
        };
        Check(
            expectedArchitecture != NativeArchitecture.Unknown &&
                buildInfo.Architecture == expectedArchitecture,
            "architecture");

        bool avxUsable = buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.AvxUsable);
        Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Avx2) || avxUsable,
            "avx2_requires_avx_state");
        Check(
            !buildInfo.CpuFeatures.HasFlag(NativeCpuFeatures.Fma) || avxUsable,
            "fma_requires_avx_state");
    }

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }

    private static void CheckThrows<TException>(Action action, string name)
        where TException : Exception
    {
        ++assertionCount;
        try
        {
            action();
            Failures.Add(name);
        }
        catch (TException)
        {
        }
    }
}
