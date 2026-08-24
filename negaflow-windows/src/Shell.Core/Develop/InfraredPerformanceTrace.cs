namespace Negaflow.Shell;

/// <summary>IR 제품 경계의 opt-in 성능 분해만 출력합니다.</summary>
internal static class InfraredPerformanceTrace
{
    internal static bool Enabled => string.Equals(
        Environment.GetEnvironmentVariable("NEGA_TIMING"),
        "1",
        StringComparison.Ordinal);

    internal static void Write(string message) =>
        Console.Error.WriteLine("[infrared host timing] " + message);
}
