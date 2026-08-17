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
            // 엔진이 뜨면 상태줄에 아무것도 덧붙이지 않습니다. macOS 는 여기에 `대기` 만
            // 냅니다 — ABI 판과 아키텍처는 사용자에게 뜻이 없는 값이고, 화면에 없는 것을
            // 지어내 붙인 것이었습니다. 진단이 필요하면 정보 패널이 낼 자리입니다.
            return new NativeEngineStatus(true, string.Empty, buildInfo);
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
