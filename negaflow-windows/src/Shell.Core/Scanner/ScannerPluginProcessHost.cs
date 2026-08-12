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
    public static async Task<ScannerPluginProcessResult> RunAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        string operation,
        IReadOnlyList<string> arguments,
        string? standardInput,
        ScannerPluginProcessLimits? limits = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(plugin);
        ArgumentNullException.ThrowIfNull(approvedIdentity);
        ArgumentException.ThrowIfNullOrWhiteSpace(operation);
        ArgumentNullException.ThrowIfNull(arguments);
        if (!ScannerPluginDiscovery.HasCurrentTrustIdentity(plugin, approvedIdentity))
        {
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
        }
        catch (Win32Exception)
        {
            return new(ScannerPluginProcessStatus.LaunchFailed, null, [], string.Empty);
        }
        catch (InvalidOperationException)
        {
            return new(ScannerPluginProcessStatus.LaunchFailed, null, [], string.Empty);
        }

        Task<StandardOutput> outputTask = ReadStandardOutputAsync(
            process.StandardOutput,
            effectiveLimits.MaximumStandardOutputBytes,
            effectiveLimits.MaximumStandardOutputLineBytes,
            cancelled.Token);
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
            StopProcessTree(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.OutputLimitExceeded, ExitCode(process), [], string.Empty);
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            StopProcessTree(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.TimedOut, ExitCode(process), [], string.Empty);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            StopProcessTree(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.Cancelled, ExitCode(process), [], string.Empty);
        }
        catch (IOException)
        {
            StopProcessTree(process);
            await DrainAfterStopAsync(outputTask, errorTask);
            return new(ScannerPluginProcessStatus.Failed, ExitCode(process), [], string.Empty);
        }
    }

    private static async Task<StandardOutput> ReadStandardOutputAsync(
        StreamReader reader,
        int maximumBytes,
        int maximumLineBytes,
        CancellationToken cancellationToken)
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
                    CommitLine(line, lines, ref consumed, maximumBytes, maximumLineBytes);
                }
                return new(lines);
            }

            for (int index = 0; index < count; ++index)
            {
                if (buffer[index] == '\n')
                {
                    CommitLine(line, lines, ref consumed, maximumBytes, maximumLineBytes);
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
        int maximumLineBytes)
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

    private static void StopProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
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
