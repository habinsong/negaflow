namespace Negaflow.Interop;

public static class NativeEngineBootstrap
{
    public static NativeBuildInfo LoadAndQuery(string nativeLibraryPath)
    {
        try
        {
            NativeLibraryLoader.EnsureLoaded(nativeLibraryPath);
            return NativeAbiReader.Read();
        }
        catch (BadImageFormatException exception)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.BinaryFormatMismatch,
                "The native engine has an invalid format or does not match the current process architecture.",
                exception);
        }
        catch (FileNotFoundException exception)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.LoadFailed,
                "The native engine could not be found.",
                exception);
        }
        catch (DllNotFoundException exception)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.LoadFailed,
                "The native engine or one of its dependencies could not be loaded.",
                exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.MissingExport,
                "The native engine does not expose the required ABI entry points.",
                exception);
        }
    }
}
