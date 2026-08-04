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
        Check(
            buildInfo.AbiVersion == new NativeAbiVersion(0, 1),
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
