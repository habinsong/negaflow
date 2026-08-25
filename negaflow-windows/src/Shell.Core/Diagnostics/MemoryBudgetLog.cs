using System.Globalization;
using System.Text;
using Negaflow.Interop;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 엔진이 보는 메모리 내역을 주기적으로 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>왜 필요한가</b> — 설치 앱이 자동 상한을 넘는데 스트레스 하네스는 안 넘었습니다. 밖에서
/// `VirtualQueryEx` 로 커밋 영역을 훑으면 "얼마나 크다" 는 보이지만 "어느 예산이 얼마를
/// 주고 있다" 는 안 보입니다. 그 두 줄을 나란히 놓아야 예산이 도는지 판정할 수 있습니다.
/// </para>
/// <para>
/// <c>memory-trace.on</c> 표시 파일이 있을 때만 켜집니다(개발자 모드가 만듭니다). 기록은
/// <c>%LOCALAPPDATA%\Negaflow\Logs\memory-budget.txt</c> 이고, 초당 한 줄을 넘지 않습니다 —
/// 이 자리는 사진 한 장마다 불리므로 묶지 않으면 파일이 순식간에 찹니다.
/// </para>
/// </remarks>
public static class MemoryBudgetLog
{
    public const string MarkerName = "memory-trace.on";

    private const long MaximumBytes = 512 * 1024;
    private static readonly Lock Gate = new();
    private static long lastWriteTicks;

    public static string Path => System.IO.Path.Combine(
        DiagnosticTraceSwitches.LogDirectory, "memory-budget.txt");

    private static bool IsEnabled()
    {
        try
        {
            return File.Exists(
                System.IO.Path.Combine(DiagnosticTraceSwitches.LogDirectory, MarkerName));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    /// <summary>한 줄 남깁니다. 표시 파일이 없거나 1초가 안 지났으면 아무 것도 하지 않습니다.</summary>
    public static void Sample(string origin)
    {
        ArgumentNullException.ThrowIfNull(origin);
        long now = Environment.TickCount64;
        long last = Interlocked.Read(ref lastWriteTicks);
        if (now - last < 1000L ||
            Interlocked.CompareExchange(ref lastWriteTicks, now, last) != last ||
            !IsEnabled())
        {
            return;
        }
        if (MemoryReportBridge.TryRead() is not { } report)
        {
            return;
        }

        static string Mb(ulong bytes) => (bytes / (1024.0 * 1024.0)).ToString(
            "N0", CultureInfo.InvariantCulture);
        string line = string.Create(
            CultureInfo.InvariantCulture,
            $"{DateTimeOffset.Now:HH:mm:ss.fff}  {origin}  " +
            $"private={Mb(report.ProcessPrivateBytes)} " +
            $"ceiling={Mb(report.AutomaticProcessCeilingBytes)} " +
            $"raw={Mb(report.DecodedSourceResidentBytes)}/{Mb(report.DecodedSourceBudgetBytes)} " +
            $"proxy={Mb(report.PreviewProxyResidentBytes)}/{Mb(report.PreviewProxyBudgetBytes)} " +
            $"display={Mb(report.DevelopedDisplayResidentBytes)}/" +
            $"{Mb(report.DevelopedDisplayBudgetBytes)} " +
            $"gpu={Mb(report.GpuPoolResidentBytes)}/{Mb(report.GpuPoolLimitBytes)} " +
            $"gpuRam={Mb(report.GpuSystemMemoryBytes)} " +
            $"overhead={Mb(report.NonCacheOverheadBytes)} " +
            $"managed={Mb((ulong)GC.GetTotalMemory(false))}{Environment.NewLine}");
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(DiagnosticTraceSwitches.LogDirectory);
                string path = Path;
                if (File.Exists(path) && new FileInfo(path).Length > MaximumBytes)
                {
                    File.Delete(path);
                }
                File.AppendAllText(path, line, Encoding.UTF8);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException or PathTooLongException)
        {
        }
    }
}
