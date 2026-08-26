using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace Negaflow.Shell;

public enum ScannerPluginProcessStatus
{
    Succeeded,
    LaunchFailed,
    Untrusted,
    TimedOut,
    Cancelled,
    OutputLimitExceeded,
    Failed,
}

public sealed record ScannerPluginProcessResult(
    ScannerPluginProcessStatus Status,
    int? ExitCode,
    IReadOnlyList<string> StandardOutputLines,
    string StandardError)
{
    public bool IsSuccess => Status == ScannerPluginProcessStatus.Succeeded && ExitCode == 0;
}

public sealed record ScannerPluginProcessLimits(
    TimeSpan WallTimeout,
    int MaximumStandardOutputBytes,
    int MaximumStandardErrorBytes,
    int MaximumStandardOutputLineBytes)
{
    public static ScannerPluginProcessLimits ForOperation(string operation) => operation switch
    {
        "detect" => new(TimeSpan.FromSeconds(90), 4 * 1024 * 1024, 512 * 1024, 256 * 1024),
        "capabilities" => new(TimeSpan.FromSeconds(180), 4 * 1024 * 1024, 512 * 1024, 256 * 1024),
        "scan" => new(TimeSpan.FromHours(2), 8 * 1024 * 1024, 512 * 1024, 256 * 1024),
        _ => throw new ArgumentOutOfRangeException(nameof(operation)),
    };
}

// The app never inherits a shell command string from an adapter. Arguments stay structured,
// process output is bounded while it is read, and a cancellation/timeout kills the complete
// child tree rather than leaving a driver helper attached to the session.
public static class ScannerPluginProcessHost
{
    /// <summary>BOM 없는 UTF-8. 플러그인 wire 계약의 인코딩입니다.</summary>
    private static readonly Encoding Utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

    public static async Task<ScannerPluginProcessResult> RunAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        string operation,
        IReadOnlyList<string> arguments,
        string? standardInput,
        ScannerPluginProcessLimits? limits = null,
        CancellationToken cancellationToken = default,
        Action<string>? onStandardOutputLine = null)
    {
        ArgumentNullException.ThrowIfNull(plugin);
        ArgumentNullException.ThrowIfNull(approvedIdentity);
        ArgumentException.ThrowIfNullOrWhiteSpace(operation);
        ArgumentNullException.ThrowIfNull(arguments);
        if (!ScannerPluginDiscovery.HasCurrentTrustIdentity(plugin, approvedIdentity))
        {
            // 실행 직전에 파일 바이트를 다시 확인합니다. 여기서 막히면 화면에는
            // ProcessFailed 로만 보이므로, 무엇이 달라졌는지 여기서만 알 수 있습니다.
            ScannerPluginTrustIdentity? current = ScannerPluginDiscovery.CurrentTrustIdentity(plugin);
            ScannerDiagnosticsLog.Write(
                $"plugin UNTRUSTED operation={operation} id={plugin.Manifest.Id} " +
                $"approvedVersion={approvedIdentity.PluginVersion ?? "-"} " +
                $"currentVersion={current?.PluginVersion ?? "-"} " +
                $"manifestSha approved={Short(approvedIdentity.ManifestSha256)} " +
                $"current={Short(current?.ManifestSha256)} " +
                $"exeSha approved={Short(approvedIdentity.ExecutableSha256)} " +
                $"current={Short(current?.ExecutableSha256)}");
            return new(ScannerPluginProcessStatus.Untrusted, null, [], string.Empty);
        }

        ScannerPluginProcessLimits effectiveLimits = limits ??
            ScannerPluginProcessLimits.ForOperation(operation);
        if (effectiveLimits.WallTimeout <= TimeSpan.Zero ||
            effectiveLimits.MaximumStandardOutputBytes <= 0 ||
            effectiveLimits.MaximumStandardErrorBytes <= 0 ||
            effectiveLimits.MaximumStandardOutputLineBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(limits));
        }

        using var timeout = new CancellationTokenSource(effectiveLimits.WallTimeout);
        using var cancelled = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, timeout.Token);
        ProcessStartInfo startInfo = new(plugin.ExecutablePath)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = standardInput is not null,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Path.GetDirectoryName(plugin.ExecutablePath)!,
            // **셋 다 UTF-8 로 못 박습니다.** 지정하지 않으면 .NET 이 콘솔 코드 페이지를
            // 씁니다 — 이 기기에서는 CP949 입니다. 플러그인 wire 계약은 UTF-8 JSON 이므로,
            // 스캔 목적지에 비ASCII 가 들어가는 순간(기본 롤 폴더가 한국어 "무제 필름")
            // 요청이 UTF-8 이 아닌 바이트로 나갑니다. 받는 쪽은 그것을 UTF-8 로 읽습니다.
            // 응답도 마찬가지로 UTF-8 이라, 읽는 인코딩이 다르면 진단 문구가 깨집니다.
            // macOS 는 `Data` 를 그대로 파이프에 쓰므로 이 문제가 없습니다.
            StandardInputEncoding = standardInput is null ? null : Utf8,
            StandardOutputEncoding = Utf8,
            StandardErrorEncoding = Utf8,
        };
        startInfo.ArgumentList.Add(operation);
        foreach (string argument in arguments)
        {
            if (argument.IndexOf('\0') >= 0)
            {
                throw new ArgumentException("Plugin arguments cannot contain NUL.", nameof(arguments));
            }
            startInfo.ArgumentList.Add(argument);
        }

        using Process process = new() { StartInfo = startInfo, EnableRaisingEvents = true };
        try
        {
            if (!process.Start())
            {
                return new(ScannerPluginProcessStatus.LaunchFailed, null, [], string.Empty);
            }
            // 앱이 **강제로** 죽어도 이 자식과 그 자손이 같이 죽게 묶습니다. 안 묶으면
            // `scanimage` 가 고아로 남아 USB 스캐너를 물고, 다음 실행의 장치 탐색이
            // 90초 시간 초과로 "스캐너 없음" 이 됩니다.
            ScannerPluginJobObject.Bind(process);
        }
        catch (Win32Exception error)
        {
            ScannerDiagnosticsLog.Write(
                $"plugin LAUNCH-FAILED operation={operation} {plugin.ExecutablePath} " +
                $"Win32 0x{error.NativeErrorCode:X8} {error.Message}");
            return new(ScannerPluginProcessStatus.LaunchFailed, null, [], string.Empty);
        }
        catch (InvalidOperationException error)
        {
            ScannerDiagnosticsLog.Write(
                $"plugin LAUNCH-FAILED operation={operation} {plugin.ExecutablePath} " +
                $"{error.GetType().Name} {error.Message}");
            return new(ScannerPluginProcessStatus.LaunchFailed, null, [], string.Empty);
        }

        Task<StandardOutput> outputTask = ReadStandardOutputAsync(
            process.StandardOutput,
            effectiveLimits.MaximumStandardOutputBytes,
            effectiveLimits.MaximumStandardOutputLineBytes,
            cancelled.Token,
            onStandardOutputLine);
        Task<string> errorTask = ReadBoundedTextAsync(
            process.StandardError,
            effectiveLimits.MaximumStandardErrorBytes,
            cancelled.Token);
        try
        {
            if (standardInput is not null)
            {
                await process.StandardInput.WriteAsync(standardInput.AsMemory(), cancelled.Token);
                await process.StandardInput.FlushAsync(cancelled.Token);
                process.StandardInput.Close();
            }

            Task exitTask = process.WaitForExitAsync(cancelled.Token);
            while (!exitTask.IsCompleted)
            {
                Task completed = await Task.WhenAny(exitTask, outputTask, errorTask);
                if (completed == outputTask && outputTask.IsFaulted)
                {
                    await outputTask;
                }
                if (completed == errorTask && errorTask.IsFaulted)
                {
                    await errorTask;
                }
                if (completed != exitTask && !outputTask.IsFaulted && !errorTask.IsFaulted)
                {
                    await exitTask;
                }
            }
            await exitTask;
            StandardOutput output = await outputTask;
            string error = await errorTask;
            return new(
                process.ExitCode == 0 ? ScannerPluginProcessStatus.Succeeded : ScannerPluginProcessStatus.Failed,
                process.ExitCode,
                output.Lines,
                error);
        }
        catch (OutputLimitException)
        {
            await StopProcessTreeAsync(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.OutputLimitExceeded, ExitCode(process), [], string.Empty);
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            await StopProcessTreeAsync(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.TimedOut, ExitCode(process), [], string.Empty);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await StopProcessTreeAsync(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.Cancelled, ExitCode(process), [], string.Empty);
        }
        catch (IOException)
        {
            await StopProcessTreeAsync(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.Failed, ExitCode(process), [], string.Empty);
        }
    }

    private static string Short(string? sha) =>
        string.IsNullOrEmpty(sha) ? "-" : sha[..Math.Min(12, sha.Length)];

    /// <param name="onLine">
    /// 줄이 하나 완성될 때마다 부릅니다. **진행률이 살아 있으려면 이것이 필요합니다** — 앞 판은
    /// 프로세스가 끝난 뒤에야 stdout 전체를 넘겼고, 그러면 진행 이벤트는 이미 지나간 이야기라
    /// 화면에 그릴 수가 없었습니다. 여기서 넘겨도 목록에는 그대로 쌓이므로 계약은 그대로입니다.
    /// </param>
    private static async Task<StandardOutput> ReadStandardOutputAsync(
        StreamReader reader,
        int maximumBytes,
        int maximumLineBytes,
        CancellationToken cancellationToken,
        Action<string>? onLine = null)
    {
        var lines = new List<string>();
        var line = new StringBuilder();
        var buffer = new char[4096];
        int consumed = 0;
        while (true)
        {
            int count = await reader.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (count == 0)
            {
                if (line.Length != 0)
                {
                    CommitLine(line, lines, ref consumed, maximumBytes, maximumLineBytes, onLine);
                }
                return new(lines);
            }

            for (int index = 0; index < count; ++index)
            {
                if (buffer[index] == '\n')
                {
                    CommitLine(line, lines, ref consumed, maximumBytes, maximumLineBytes, onLine);
                    continue;
                }
                // A UTF-8 scalar takes at least one byte. This caps storage before a newline
                // appears; the exact UTF-8 byte budget is checked when the line is committed.
                if (line.Length >= maximumLineBytes)
                {
                    throw new OutputLimitException();
                }
                line.Append(buffer[index]);
            }
        }
    }

    private static void CommitLine(
        StringBuilder pending,
        List<string> lines,
        ref int consumed,
        int maximumBytes,
        int maximumLineBytes,
        Action<string>? onLine = null)
    {
        if (pending.Length != 0 && pending[^1] == '\r')
        {
            --pending.Length;
        }
        string line = pending.ToString();
        pending.Clear();
        int lineBytes = Encoding.UTF8.GetByteCount(line) + 1;
        if (lineBytes > maximumLineBytes || lineBytes > maximumBytes - consumed)
        {
            throw new OutputLimitException();
        }
        consumed += lineBytes;
        lines.Add(line);
        // 듣는 쪽이 던지면 스캔이 끊깁니다. 진행률 표시가 스캔을 죽여서는 안 됩니다.
        try
        {
            onLine?.Invoke(line);
        }
        catch (Exception error)
        {
            ScannerDiagnosticsLog.Write($"progress listener threw: {error.GetType().Name} {error.Message}");
        }
    }

    private static async Task<string> ReadBoundedTextAsync(
        StreamReader reader,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        var output = new StringBuilder();
        var buffer = new char[4096];
        int consumed = 0;
        while (true)
        {
            int count = await reader.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (count == 0)
            {
                return output.ToString();
            }

            int bytes = Encoding.UTF8.GetByteCount(buffer.AsSpan(0, count));
            if (bytes > maximumBytes - consumed)
            {
                throw new OutputLimitException();
            }
            consumed += bytes;
            output.Append(buffer, 0, count);
        }
    }

    /// <summary>
    /// 플러그인을 멈춥니다. <b>정상 종료를 먼저 청하고</b>, 그래도 안 끝날 때만 죽입니다.
    /// </summary>
    /// <remarks>
    /// 곧바로 <see cref="Process.Kill(bool)"/> 하면 <c>sane_cancel()</c> 이 불리지 않아, 전송
    /// 도중에 죽은 스캐너가 전원을 다시 넣기 전까지 어떤 요청에도 답하지 않습니다.
    /// <see cref="ScannerPluginGracefulStop"/> 주석에 보내는 방법과, 앞서 이 자리에서 앱이
    /// 꺼졌던 이유가 적혀 있습니다.
    /// </remarks>
    private static async Task StopProcessTreeAsync(Process process)
    {
        try
        {
            if (process.HasExited)
            {
                return;
            }
            if (await ScannerPluginGracefulStop
                    .TryStopAsync(process, ScannerPluginGracefulStop.DefaultGrace)
                    .ConfigureAwait(false))
            {
                ScannerDiagnosticsLog.Write(
                    "plugin stopped gracefully - the scanner was told to cancel");
                return;
            }
            // 여기까지 왔으면 강제 종료입니다. 그 사실을 남깁니다 - 이 뒤에 장치가 물리면
            // 원인을 추측하지 않아도 됩니다.
            ScannerDiagnosticsLog.Write(
                "plugin did not stop in time - forcing the tree down; the scanner may need a power cycle");
            process.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
        }
        catch (Win32Exception)
        {
        }
    }

    private static int? ExitCode(Process process)
    {
        try
        {
            return process.HasExited ? process.ExitCode : null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    private static async Task DrainAfterStopAsync(params Task[] tasks)
    {
        try
        {
            await Task.WhenAll(tasks);
        }
        catch (Exception error) when (error is OperationCanceledException or OutputLimitException)
        {
        }
    }

    private sealed record StandardOutput(IReadOnlyList<string> Lines);

    private sealed class OutputLimitException : Exception
    {
    }
}
