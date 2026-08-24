using System.Globalization;
using System.IO;

namespace Negaflow.Shell;

/// <summary>
/// 미리보기 공백 캔버스 원인을 파일로 남깁니다.
/// </summary>
/// <remarks>
/// 기본은 꺼짐입니다. 설정 · 일반의 "개발자 모드" 를 켜면 표시 파일
/// <c>preview-trace.on</c> 이 생기고 그때부터 기록합니다. 늘 쓰면 현상할 때마다 디스크에
/// 줄이 쌓여 느려집니다.
/// </remarks>
public static class PreviewTrace
{
    private static readonly object Gate = new();

    private static readonly Lazy<bool> Enabled = new(
        () =>
        {
            try
            {
                string localMarker = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Negaflow", "Logs", "preview-trace.on");
                string packageMarker = System.IO.Path.Combine(
                    AppContext.BaseDirectory,
                    "preview-trace.on");
                return System.IO.File.Exists(localMarker) ||
                    System.IO.File.Exists(packageMarker);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException
                or ArgumentException or NotSupportedException or PathTooLongException)
            {
                return false;
            }
        },
        isThreadSafe: true);
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs",
        "preview-trace.txt");

    /// <summary>
    /// 기록 중인지입니다. 인자를 만드는 비용이 큰 자리는 이것으로 먼저 막습니다 — 인자는
    /// <see cref="Write"/> 안의 검사보다 <b>먼저</b> 계산되기 때문입니다.
    /// </summary>
    public static bool IsEnabled => Enabled.Value;

    public static void Write(string message)
    {
        if (!Enabled.Value)
        {
            return;
        }
        try
        {
            string line = DateTime.UtcNow.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) +
                " " + Environment.CurrentManagedThreadId + " " + message + Environment.NewLine;
            lock (Gate)
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                File.AppendAllText(Path, line);
            }
        }
        catch
        {
        }
    }
}
