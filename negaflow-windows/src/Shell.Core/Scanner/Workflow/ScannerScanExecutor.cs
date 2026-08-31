namespace Negaflow.Shell;

internal static class ScannerScanExecutor
{
    /// <summary>진행 줄을 읽어 넘기는 손입니다. 듣는 쪽이 없으면 만들지 않습니다.</summary>
    private static Action<string>? ProgressLineReader(
        Guid requestId,
        Action<ScanProgressReport>? onProgress)
    {
        if (onProgress is null)
        {
            return null;
        }
        return line =>
        {
            if (ScannerPluginProgressReader.TryRead(line, requestId) is { } report)
            {
                onProgress(report);
            }
        };
    }

    internal static async Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken,
        Action<ScanProgressReport>? onProgress = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!ScannerScanCodec.TryBuild(
                request,
                out ScannerPluginClient.ScanWire? wire,
                out string? stagingDirectory,
                out string? refusal))
        {
            // 거절한 **조건 이름**을 그대로 답니다. `CapabilityMismatch` 한 단어로는
            // 열몇 가지 중 무엇이 걸렸는지 알 수 없습니다.
            ScannerDiagnosticsLog.WriteFailure(
                $"TryBuild (CapabilityMismatch: {refusal ?? "unknown"})",
                plugin,
                request,
                null,
                null,
                null);
            return new(ScannerPluginScanStatus.CapabilityMismatch, null, null, null);
        }
        ScannerPluginClient.ScanWire scanWire = wire!;
        string wireJson = ScannerScanCodec.Serialize(scanWire);

        try
        {
            Directory.CreateDirectory(stagingDirectory!);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ScannerDiagnosticsLog.Write(
                $"staging create failed: {error.GetType().Name} {error.Message}");
            ScannerDiagnosticsLog.WriteFailure(
                "StagingCreateFailed", plugin, request, wireJson, stagingDirectory, null);
            return new(ScannerPluginScanStatus.StagingCreateFailed, null, null, null);
        }

        try
        {
            ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
                plugin,
                approvedIdentity,
                "scan",
                [request.Device.Id],
                wireJson,
                cancellationToken: cancellationToken,
                // 스캔이 **도는 동안** 진행 줄을 읽어 넘깁니다. 끝난 뒤에 넘기면 이미 지나간
                // 이야기라 화면에 그릴 수가 없습니다.
                onStandardOutputLine: ProgressLineReader(scanWire.RequestId, onProgress));
            if (!process.IsSuccess)
            {
                // **한 이름으로 접지 않습니다.** 프로세스는 이미 갈래를 알고 있으므로 그대로
                // 옮깁니다 - 앞 판은 전부 `ProcessFailed` 였고, 사용자가 스캔을 멈춘 것까지
                // 실패로 보였습니다.
                ScannerPluginScanStatus status = process.Status switch
                {
                    ScannerPluginProcessStatus.LaunchFailed =>
                        ScannerPluginScanStatus.ProcessLaunchFailed,
                    ScannerPluginProcessStatus.Untrusted =>
                        ScannerPluginScanStatus.PluginUntrusted,
                    ScannerPluginProcessStatus.TimedOut =>
                        ScannerPluginScanStatus.ProcessTimedOut,
                    ScannerPluginProcessStatus.Cancelled =>
                        ScannerPluginScanStatus.Cancelled,
                    ScannerPluginProcessStatus.OutputLimitExceeded =>
                        ScannerPluginScanStatus.ProcessOutputLimitExceeded,
                    ScannerPluginProcessStatus.Succeeded or ScannerPluginProcessStatus.Failed =>
                        ScannerPluginScanStatus.ProcessExitedWithError,
                    _ => ScannerPluginScanStatus.ProcessFailed,
                };
                ScannerDiagnosticsLog.WriteFailure(
                    $"{status} (process={process.Status} exit={process.ExitCode?.ToString() ?? "none"})",
                    plugin,
                    request,
                    wireJson,
                    stagingDirectory,
                    process);
                return new(status, process, null, null);
            }

            ScannerPluginStreamValidation stream = ScannerPluginProtocol.ValidateV2(
                process.StandardOutputLines,
                scanWire.RequestId);
            if (!stream.IsSuccess)
            {
                ScannerDiagnosticsLog.WriteFailure(
                    $"ProtocolViolation ({stream.Status})",
                    plugin,
                    request,
                    wireJson,
                    stagingDirectory,
                    process);
                return new(ScannerPluginScanStatus.ProtocolViolation, process, stream.Status, null);
            }
            ScannerPluginStreamEvent terminal = stream.TerminalEvent!;
            if (terminal.Type == "error")
            {
                ScannerDiagnosticsLog.WriteFailure(
                    "PluginError", plugin, request, wireJson, stagingDirectory, process);
                return new(ScannerPluginScanStatus.PluginError, process, stream.Status, null);
            }
            if (!ScannerScanCodec.TryValidateV2Result(
                    terminal.Payload,
                    scanWire,
                    out string? infraredPath,
                    out ScannerArtifactRequirements? artifactRequirements,
                    out ScannerPluginScanArea? appliedScanArea,
                    out string? mismatch))
            {
                // **어긋난 필드 이름을 그대로 답니다.** `ResultMismatch` 한 단어만 남기면
                // 열몇 가지 검사 중 무엇이 틀렸는지 기록으로 좁힐 수 없습니다.
                ScannerDiagnosticsLog.WriteFailure(
                    $"ResultMismatch ({mismatch ?? "unknown"})",
                    plugin,
                    request,
                    wireJson,
                    stagingDirectory,
                    process);
                return new(ScannerPluginScanStatus.ResultMismatch, process, stream.Status, null);
            }

            ScannerArtifactCommitResult committed = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(stagingDirectory!, scanWire.OutputPath, infraredPath),
                request.DestinationVisiblePath,
                requirements: artifactRequirements);
            if (!committed.IsSuccess)
            {
                ScannerDiagnosticsLog.WriteFailure(
                    $"ArtifactCommitFailed ({committed.Status})",
                    plugin,
                    request,
                    wireJson,
                    stagingDirectory,
                    process);
            }
            else
            {
                ScannerDiagnosticsLog.Write(
                    $"scan ok device={request.Device.Id} dpi={request.ResolutionDpi} " +
                    $"depth={request.BitDepth} preview={request.Preview} " +
                    $"-> {request.DestinationVisiblePath}");
            }
            return new(
                committed.IsSuccess
                    ? ScannerPluginScanStatus.Completed
                    : ScannerPluginScanStatus.ArtifactCommitFailed,
                process,
                stream.Status,
                committed,
                appliedScanArea);
        }
        finally
        {
            try
            {
                if (Directory.Exists(stagingDirectory))
                {
                    Directory.Delete(stagingDirectory, recursive: true);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
            }
        }
    }
}
