using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 앱이 뜨는 동안 <b>어느 단계가 얼마나 걸렸는지</b> 남깁니다.
/// </summary>
/// <remarks>
/// **켤 때마다 검은 화면이 몇 초 머무는 것을 숫자로 잡기 위한 자리입니다.**
///
/// 밖에서 프로세스를 지켜보는 것으로는 창이 늦게 뜨는 것까지만 보이고, 그 안에서 무엇이 시간을
/// 먹는지는 알 수 없습니다 — 실제로 밖에서 재면 창까지 2.45 초이고 무응답 표본이 하나도 없는데
/// 사용자는 검은 화면을 봅니다. 그 간극이 여기 남습니다.
///
/// <see cref="ThumbnailTrace"/> 와 달리 <b>켜는 파일이 필요 없습니다.</b> 시작은 한 번뿐이고 줄
/// 수도 몇 십 줄이라, 켜 두는 것을 잊어 다음 재현을 놓치는 편이 훨씬 비쌉니다.
/// </remarks>
public static class StartupTrace
{
    private static readonly Lock Gate = new();
    private static readonly Stopwatch Since = Stopwatch.StartNew();
    private static readonly Lazy<string?> Destination = new(Resolve, isThreadSafe: true);

    /// <summary>한 단계를 남깁니다. 프로세스가 뜬 뒤로 흐른 시간이 함께 적힙니다.</summary>
    public static void Mark(string stage)
    {
        if (Destination.Value is not { } path)
        {
            return;
        }
        string line = string.Create(
            CultureInfo.InvariantCulture,
            $"{Since.Elapsed.TotalSeconds,8:F3}  t{Environment.CurrentManagedThreadId,-3}  {stage}{Environment.NewLine}");
        try
        {
            lock (Gate)
            {
                File.AppendAllText(path, line, Encoding.UTF8);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 진단이 제품 동작을 막아서는 안 됩니다.
        }
    }

    /// <summary>
    /// 한 구간을 재고 끝날 때 남깁니다. <c>using</c> 으로 감싸십시오.
    /// </summary>
    public static IDisposable Measure(string stage) => new Span(stage);

    private sealed class Span : IDisposable
    {
        private readonly string stage;
        private readonly long started;

        internal Span(string stage)
        {
            this.stage = stage;
            started = Stopwatch.GetTimestamp();
            Mark(stage + " begin");
        }

        public void Dispose() => Mark(string.Create(
            CultureInfo.InvariantCulture,
            $"{stage} end ({Stopwatch.GetElapsedTime(started).TotalMilliseconds:F1} ms)"));
    }

    private static string? Resolve()
    {
        try
        {
            string logs = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            Directory.CreateDirectory(logs);
            string path = Path.Combine(logs, "startup-trace.txt");
            // 시작마다 새로 씁니다 - 지난 실행이 섞이면 어느 줄이 이번 것인지 가릴 수 없습니다.
            File.WriteAllText(
                path,
                string.Create(
                    CultureInfo.InvariantCulture,
                    $"# {DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff} pid={Environment.ProcessId}{Environment.NewLine}"),
                Encoding.UTF8);
            return path;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
