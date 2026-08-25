namespace Negaflow.Shell;

internal static class ScannerScanExecutor
{
    internal static async Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!ScannerScanCodec.TryBuild(
                request,
                out ScannerPluginClient.ScanWire? wire,
                out string? stagingDirectory))
        {
            ScannerDiagnosticsLog.WriteFailure(
                "TryBuild (CapabilityMismatch)", plugin, request, null, null, null);
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
                cancellationToken: cancellationToken);
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
                    out ScannerPluginScanArea? appliedScanArea))
            {
                ScannerDiagnosticsLog.WriteFailure(
                    "ResultMismatch", plugin, request, wireJson, stagingDirectory, process);
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
