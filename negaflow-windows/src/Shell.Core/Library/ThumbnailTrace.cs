using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace Negaflow.Shell.Library;

/// <summary>
/// 썸네일·프리뷰 갱신 경로의 진단 추적입니다. 무엇이 실제로 일어났는지 파일로 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 기본은 <b>꺼짐</b>입니다. <c>%LOCALAPPDATA%\Negaflow\Logs\thumbnail-trace.on</c> 파일이
/// 있을 때만 켜지고, 그때만 <c>thumbnail-trace.log</c> 에 씁니다. 켜져 있지 않으면
/// <see cref="Write"/> 는 문자열조차 만들지 않습니다.
/// </para>
/// <para>
/// 화면에서 벌어지는 일은 헤드리스 하네스로 재현할 수 없습니다. 그래서 추정 대신 실제 실행이
/// 남긴 줄을 읽습니다.
/// </para>
/// </remarks>
public static class ThumbnailTrace
{
    private static readonly Lock Gate = new();
    private static readonly Stopwatch Since = Stopwatch.StartNew();
    private static readonly Lazy<string?> Destination = new(Resolve, isThreadSafe: true);

    public static bool IsEnabled => Destination.Value is not null;

    public static void Write(string message)
    {
        if (Destination.Value is not { } path)
        {
            return;
        }
        string line = string.Create(
            CultureInfo.InvariantCulture,
            $"{Since.Elapsed.TotalSeconds,9:F3}  t{Environment.CurrentManagedThreadId,-3}  {message}{Environment.NewLine}");
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

    private static string? Resolve()
    {
        try
        {
            string logs = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            if (!File.Exists(Path.Combine(logs, "thumbnail-trace.on")))
            {
                return null;
            }
            Directory.CreateDirectory(logs);
            return Path.Combine(logs, "thumbnail-trace.log");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
