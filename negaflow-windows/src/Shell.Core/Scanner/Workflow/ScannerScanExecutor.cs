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
            return new(ScannerPluginScanStatus.CapabilityMismatch, null, null, null);
        }
        ScannerPluginClient.ScanWire scanWire = wire!;

        try
        {
            Directory.CreateDirectory(stagingDirectory!);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return new(ScannerPluginScanStatus.StagingCreateFailed, null, null, null);
        }

        try
        {
            ScannerPluginProcessResult process = await ScannerPluginProcessHost.RunAsync(
                plugin,
                approvedIdentity,
                "scan",
                [request.Device.Id],
                ScannerScanCodec.Serialize(scanWire),
                cancellationToken: cancellationToken);
            if (!process.IsSuccess)
            {
                return new(ScannerPluginScanStatus.ProcessFailed, process, null, null);
            }

            ScannerPluginStreamValidation stream = ScannerPluginProtocol.ValidateV2(
                process.StandardOutputLines,
                scanWire.RequestId);
            if (!stream.IsSuccess)
            {
                return new(ScannerPluginScanStatus.ProtocolViolation, process, stream.Status, null);
            }
            ScannerPluginStreamEvent terminal = stream.TerminalEvent!;
            if (terminal.Type == "error")
            {
                return new(ScannerPluginScanStatus.PluginError, process, stream.Status, null);
            }
            if (!ScannerScanCodec.TryValidateV2Result(
                    terminal.Payload,
                    scanWire,
                    out string? infraredPath,
                    out ScannerArtifactRequirements? artifactRequirements))
            {
                return new(ScannerPluginScanStatus.ResultMismatch, process, stream.Status, null);
            }

            ScannerArtifactCommitResult committed = ScannerArtifactTransaction.Commit(
                new ScannerStagedArtifacts(stagingDirectory!, scanWire.OutputPath, infraredPath),
                request.DestinationVisiblePath,
                requirements: artifactRequirements);
            return new(
                committed.IsSuccess
                    ? ScannerPluginScanStatus.Completed
                    : ScannerPluginScanStatus.ArtifactCommitFailed,
                process,
                stream.Status,
                committed);
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
