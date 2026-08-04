using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record NativeEngineStatus(
    bool IsAvailable,
    string Detail,
    NativeBuildInfo? BuildInfo);

public sealed class NativeEngineStatusService
{
    public NativeEngineStatus Probe()
    {
        string nativeLibraryPath = Path.Combine(AppContext.BaseDirectory, "Negaflow.Native.dll");
        try
        {
            NativeBuildInfo buildInfo = NativeEngineBootstrap.LoadAndQuery(nativeLibraryPath);
            return new NativeEngineStatus(
                true,
                $"ABI {buildInfo.AbiVersion} · {buildInfo.Architecture}",
                buildInfo);
        }
        catch (NativeBootstrapException exception)
        {
            return new NativeEngineStatus(
                false,
                exception.Failure.ToString(),
                null);
        }
        catch (Exception exception) when (
            exception is ArgumentException or InvalidOperationException or PlatformNotSupportedException)
        {
            return new NativeEngineStatus(
                false,
                exception.GetType().Name,
                null);
        }
    }
}
