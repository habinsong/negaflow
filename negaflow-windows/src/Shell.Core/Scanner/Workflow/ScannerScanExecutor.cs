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
                // `ProcessFailed` 는 서로 다른 원인을 한 이름으로 접습니다 — 실행 실패,
                // 신뢰 검사 거부, 시간 초과, 출력 상한 초과, 그리고 플러그인이 0 이 아닌
                // 코드로 끝난 경우가 모두 여기로 옵니다. 어느 쪽인지는 로그에만 있습니다.
                ScannerDiagnosticsLog.WriteFailure(
                    "ProcessFailed", plugin, request, wireJson, stagingDirectory, process);
                return new(ScannerPluginScanStatus.ProcessFailed, process, null, null);
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
