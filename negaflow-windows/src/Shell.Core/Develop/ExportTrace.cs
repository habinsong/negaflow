using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;

namespace Negaflow.Shell;

/// <summary>
/// 내보내기 단추를 누른 뒤 <b>어느 단계가 얼마나 걸렸는지</b> 남깁니다.
/// </summary>
/// <remarks>
/// **켜는 파일이 필요 없습니다.** <see cref="PreviewTrace"/> 는 현상할 때마다 줄이 쌓여 꺼
/// 두지만, 내보내기는 사용자가 단추를 누를 때만 도는 일이고 한 번에 남는 줄도 열 줄 남짓이라
/// 늘 켜 두는 편이 훨씬 쌉니다 — 꺼 두면 "눌렀는데 십 초가 걸린다" 는 다음 재현을 또 놓칩니다.
/// <see cref="Diagnostics.StartupTrace"/> 와 같은 이유입니다.
///
/// 파일은 이어 씁니다. 한 번의 실행이 아니라 <b>여러 번 누른 것</b>을 나란히 놓고 봐야
/// 어느 자리가 매번 비싼지 가려집니다. 대신 <see cref="MaximumBytes"/> 를 넘으면 처음부터
/// 다시 씁니다.
/// </remarks>
public static class ExportTrace
{
    private const long MaximumBytes = 4L * 1024 * 1024;

    private static readonly Lock Gate = new();

    private static readonly Lazy<string?> Destination = new(Resolve, isThreadSafe: true);

    /// <summary>한 줄 남깁니다.</summary>
    public static void Write(string message)
    {
        if (Destination.Value is not { } path)
        {
            return;
        }
        string line = string.Create(
            CultureInfo.InvariantCulture,
            $"{DateTime.Now:HH:mm:ss.fff}  t{Environment.CurrentManagedThreadId,-3}  {message}{Environment.NewLine}");
        try
        {
            lock (Gate)
            {
                if (new FileInfo(path) is { Exists: true, Length: > MaximumBytes })
                {
                    File.WriteAllText(path, string.Empty, Encoding.UTF8);
                }
                File.AppendAllText(path, line, Encoding.UTF8);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 진단이 제품 동작을 막아서는 안 됩니다.
        }
    }

    /// <summary>한 구간을 재고 끝날 때 남깁니다. <c>using</c> 으로 감싸십시오.</summary>
    public static IDisposable Measure(string stage) => new Span(stage);

    private sealed class Span : IDisposable
    {
        private readonly string stage;
        private readonly long started;
        private bool written;

        internal Span(string stage)
        {
            this.stage = stage;
            started = Stopwatch.GetTimestamp();
        }

        /// <summary>
        /// 한 구간은 <b>한 줄</b>입니다. 두 번 놓아도 두 번 적지 않습니다.
        /// </summary>
        /// <remarks>
        /// 일찍 끝내려고 <c>Dispose()</c> 를 직접 부른 뒤 <c>using</c> 이 범위 끝에서 한 번 더
        /// 놓는 자리가 있습니다(`PrintSheetWriter` 의 <c>develop sources</c> · <c>read sizes</c>).
        /// 그때 같은 이름이 서로 다른 시간으로 두 번 찍혀, 기록만 보면 단계가 두 번 돈 것처럼
        /// 보였습니다 — 실측 기록이 거짓말을 하면 그 기록으로 아무것도 못 잽니다.
        /// </remarks>
        public void Dispose()
        {
            if (written)
            {
                return;
            }
            written = true;
            Write(string.Create(
                CultureInfo.InvariantCulture,
                $"{stage} {Stopwatch.GetElapsedTime(started).TotalMilliseconds:F1} ms"));
        }
    }

    private static string? Resolve()
    {
        try
        {
            string logs = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            Directory.CreateDirectory(logs);
            return System.IO.Path.Combine(logs, "export-trace.txt");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
