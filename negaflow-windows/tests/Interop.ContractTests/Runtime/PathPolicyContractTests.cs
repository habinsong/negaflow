using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class PathPolicyContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(NativeMethods.FileName),
            "relative_path_rejected");

        string wrongName = Path.Combine(Path.GetTempPath(), "not-negaflow-native.dll");
        context.CheckThrows<ArgumentException>(
            () => NativeLibraryLoader.EnsureLoaded(wrongName),
            "wrong_file_name_rejected");

        string missingLibrary = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-missing-{Guid.NewGuid():N}",
            NativeMethods.FileName);
        try
        {
            NativeEngineBootstrap.LoadAndQuery(missingLibrary);
            context.Check(false, "missing_library_classified");
        }
        catch (NativeBootstrapException exception)
            when (exception.Failure == NativeBootstrapFailure.LoadFailed)
        {
            context.Check(true, "missing_library_classified");
        }
    }
}
