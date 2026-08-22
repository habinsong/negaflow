using System.Globalization;
using System.Text;

namespace Negaflow.Shell;

/// <summary>
/// 스캔이 실패했을 때 무엇이 왜 실패했는지 파일로 남깁니다.
/// </summary>
/// <remarks>
/// <para>
/// 화면에는 <c>ProcessFailed</c> 같은 한 단어만 나옵니다. 그런데 그 한 단어에는
/// <b>서로 다른 원인이 여럿</b> 묶여 있습니다 — 플러그인이 0 이 아닌 코드로 끝난 경우,
/// 신뢰 검사에서 막힌 경우, 실행 자체가 안 된 경우가 모두 같은 이름으로 나옵니다
/// (<see cref="ScannerPluginProcessResult.IsSuccess"/> 하나로 접히기 때문입니다).
/// 사용자도 개발자도 그 이름만으로는 다음에 무엇을 볼지 알 수 없습니다.
/// </para>
/// <para>
/// 그래서 실패한 실행마다 플러그인 경로·요청 wire·종료 코드·stderr 를
/// <c>%LOCALAPPDATA%\Negaflow\Logs\scanner-failure.txt</c> 에 남깁니다. 성공은 한 줄만
/// 남겨 마지막으로 통한 요청이 무엇이었는지 대조할 수 있게 합니다.
/// </para>
/// </remarks>
public static class ScannerDiagnosticsLog
{
    private const int MaximumStandardErrorCharacters = 4000;
    private static readonly Lock Gate = new();

    public static void Write(string message)
    {
        ArgumentNullException.ThrowIfNull(message);
        if (Destination() is not { } path)
        {
            return;
        }
        string line = string.Create(
            CultureInfo.InvariantCulture,
            $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff}  {message}{Environment.NewLine}");
        try
        {
            lock (Gate)
            {
                File.AppendAllText(path, line, Encoding.UTF8);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 진단이 스캔을 막아서는 안 됩니다.
        }
    }

    /// <summary>실패한 실행 하나를 한 덩어리로 남깁니다.</summary>
    public static void WriteFailure(
        string stage,
        InstalledScannerPlugin? plugin,
        ScannerPluginScanRequest? request,
        string? wireJson,
        string? stagingDirectory,
        ScannerPluginProcessResult? process)
    {
        StringBuilder report = new();
        report.Append("scan FAILED at ").Append(stage);
        if (plugin is not null)
        {
            report.Append(Environment.NewLine)
                .Append("  plugin      : ").Append(plugin.Manifest.Id)
                .Append(" v").Append(plugin.Manifest.PluginVersion ?? "-")
                .Append(" protocol=").Append(plugin.Manifest.ResolvedProtocolVersion)
                .Append(Environment.NewLine)
                .Append("  executable  : ").Append(plugin.ExecutablePath)
                .Append(" exists=").Append(File.Exists(plugin.ExecutablePath));
        }
        if (request is not null)
        {
            report.Append(Environment.NewLine)
                .Append("  device      : ").Append(request.Device.Id)
                .Append(Environment.NewLine)
                .Append("  destination : ").Append(request.DestinationVisiblePath)
                .Append(Environment.NewLine)
                .Append("  directory   : ")
                .Append(DescribeDirectory(Path.GetDirectoryName(request.DestinationVisiblePath)));
        }
        if (stagingDirectory is not null)
        {
            report.Append(Environment.NewLine)
                .Append("  staging     : ").Append(stagingDirectory)
                .Append(" exists=").Append(Directory.Exists(stagingDirectory));
        }
        if (wireJson is not null)
        {
            report.Append(Environment.NewLine)
                .Append("  request     : ").Append(Elide(wireJson));
        }
        if (process is not null)
        {
            report.Append(Environment.NewLine)
                .Append("  process     : ").Append(process.Status)
                .Append(" exit=").Append(process.ExitCode?.ToString(CultureInfo.InvariantCulture) ?? "none")
                .Append(" stdoutLines=").Append(process.StandardOutputLines.Count);
            if (process.StandardError is { Length: > 0 } error)
            {
                report.Append(Environment.NewLine)
                    .Append("  stderr      : ")
                    .Append(Truncate(error.Trim(), MaximumStandardErrorCharacters));
            }
            foreach (string stdout in process.StandardOutputLines.TakeLast(3))
            {
                report.Append(Environment.NewLine)
                    .Append("  stdout      : ").Append(Truncate(stdout, 600));
            }
        }
        Write(report.ToString());
    }

    /// <summary>
    /// <c>capabilityToken</c> 은 장치의 SANE 옵션 덤프라 수천 자입니다. 진단에 필요한 것은
    /// "실렸는가" 뿐이므로 길이만 남깁니다.
    /// </summary>
    private static string Elide(string wireJson)
    {
        const string key = "\"capabilityToken\":\"";
        int start = wireJson.IndexOf(key, StringComparison.Ordinal);
        if (start < 0)
        {
            return Truncate(wireJson, 2000);
        }
        int valueStart = start + key.Length;
        int end = wireJson.IndexOf('"', valueStart);
        if (end < 0)
        {
            return Truncate(wireJson, 2000);
        }
        return Truncate(
            string.Concat(
                wireJson.AsSpan(0, valueStart),
                $"<{end - valueStart} chars>",
                wireJson.AsSpan(end)),
            2000);
    }

    private static string DescribeDirectory(string? directory)
    {
        if (string.IsNullOrEmpty(directory))
        {
            return "<none>";
        }
        bool exists = Directory.Exists(directory);
        if (!exists)
        {
            return directory + " (missing)";
        }
        try
        {
            string probe = Path.Combine(directory, $".negaflow-write-probe-{Guid.NewGuid():N}");
            File.WriteAllBytes(probe, []);
            File.Delete(probe);
            return directory + " (writable)";
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return directory + " (NOT writable: " + error.GetType().Name + ")";
        }
    }

    private static string Truncate(string value, int maximum) =>
        value.Length <= maximum ? value : value[..maximum] + "…";

    private static string? Destination()
    {
        try
        {
            string logs = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Negaflow",
                "Logs");
            Directory.CreateDirectory(logs);
            return Path.Combine(logs, "scanner-failure.txt");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return null;
        }
    }
}
