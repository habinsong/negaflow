using System.Globalization;
using System.IO;

namespace Negaflow.Shell;

/// <summary>미리보기 공백 캔버스 원인을 파일로 남깁니다. 확정 후 지웁니다.</summary>
public static class PreviewTrace
{
    private static readonly object Gate = new();
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs",
        "preview-trace.txt");

    public static void Write(string message)
    {
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
