using System.Text;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 설정이 실제로 바뀔 때마다 한 줄 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 늘 켜 둡니다. 사람이 설정을 바꾸는 일은 초당 수천 번 일어나지 않으므로 값이 싸고, 대신
/// "눌렀는데 안 먹는다" 를 추측 없이 가릅니다 - 줄이 남으면 저장까지 간 것이고, 없으면
/// 손잡이가 아예 안 불린 것입니다.
/// </para>
/// <para>
/// 파일은 <c>%LOCALAPPDATA%\Negaflow\Logs\settings-change.txt</c> 이고, 64KB 를 넘으면
/// 앞을 버립니다. 값 자체를 적지 않고 <b>무엇이 바뀌었는지</b>만 적습니다.
/// </para>
/// </remarks>
public static class SettingsChangeLog
{
    private const long MaximumBytes = 64 * 1024;
    private static readonly Lock Gate = new();

    public static string Path => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs",
        "settings-change.txt");

    public static void Write(string message)
    {
        ArgumentNullException.ThrowIfNull(message);
        try
        {
            string path = Path;
            string line = string.Create(
                System.Globalization.CultureInfo.InvariantCulture,
                $"{DateTimeOffset.Now:HH:mm:ss.fff}  {message}{Environment.NewLine}");
            lock (Gate)
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
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
            // 기록이 설정 저장을 막아서는 안 됩니다.
        }
    }
}
