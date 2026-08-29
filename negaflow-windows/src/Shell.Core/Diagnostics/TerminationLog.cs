using System.Globalization;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// 앱을 닫을 때 결함 굽기가 어떻게 끝났는지 한 줄 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 늘 켜 둡니다. 종료는 자주 일어나지 않아 값이 싸고, 대신 "닫으려는데 안 닫힌다" 를 추측
/// 없이 가릅니다 — 앞 판은 이 실패를 개발자 모드에서만 켜지는 기록에만 적어서, 실기에서는
/// 왜 막혔는지 어디에도 남지 않았습니다.
/// </para>
/// <para>
/// 파일은 <c>%LOCALAPPDATA%\Negaflow\Logs\termination.txt</c> 이고, 64KB 를 넘으면 앞을
/// 버립니다.
/// </para>
/// </remarks>
public static class TerminationLog
{
    private const long MaximumBytes = 64 * 1024;

    private static readonly Lock Gate = new();

    public static string Path => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs",
        "termination.txt");

    public static void Write(string message)
    {
        ArgumentNullException.ThrowIfNull(message);
        try
        {
            string path = Path;
            string line = string.Create(
                CultureInfo.InvariantCulture,
                $"{DateTimeOffset.Now:HH:mm:ss.fff}  {message}{Environment.NewLine}");
            lock (Gate)
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
                if (File.Exists(path) && new FileInfo(path).Length > MaximumBytes)
                {
                    File.Delete(path);
                }
                File.AppendAllText(path, line);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            // 기록이 제품 동작을 막아서는 안 됩니다. 특히 여기는 종료 경로입니다.
        }
    }
}
