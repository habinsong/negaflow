namespace Negaflow.Shell;

internal sealed record ScanRunExecution(
    ScanRunOutcome Outcome,
    string? FailureName,
    string? PreviewPath);

internal static class ScanRunCoordinator
{
    internal static async Task<ScanRunExecution> RunAsync(
        IScannerPluginGateway gateway,
        Func<(InstalledScannerPlugin? Plugin, ScannerPluginTrustIdentity? Identity)> approvedPlugin,
        LibraryHostService library,
        Func<int, string> destinationForIndex,
        Func<bool, string, int, ScannerPluginScanRequest?> buildRequest,
        bool preview,
        int requested,
        CancellationToken cancellationToken)
    {
        int published = 0;
        string? failureName = null;
        string? previewPath = null;
        ScannerPluginLibraryScanStatus? lastStatus = null;
        ScannerPluginScanStatus? lastScanStatus = null;
        for (int index = 0; index < requested; ++index)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (buildRequest(preview, destinationForIndex(index), index) is not { } request)
            {
                break;
            }
            (InstalledScannerPlugin? plugin, ScannerPluginTrustIdentity? identity) = approvedPlugin();
            if (plugin is null || identity is null)
            {
                break;
            }
            if (preview)
            {
                ScannerPluginScanResult scanned = await gateway
                    .ScanAsync(plugin, identity, request, cancellationToken)
                    .ConfigureAwait(false);
                lastScanStatus = scanned.Status;
                if (!scanned.IsSuccess)
                {
                    failureName = scanned.Status.ToString();
                    break;
                }
                previewPath = scanned.ArtifactCommit?.Artifacts?.VisiblePath;
                ++published;
                continue;
            }

            ScannerPluginLibraryScanResult result = await gateway
                .ScanAndPublishAsync(plugin, identity, request, library, cancellationToken)
                .ConfigureAwait(false);
            lastStatus = result.Status;
            lastScanStatus = result.Scan.Status;
            if (!result.IsSuccess)
            {
                failureName = result.Scan.Status == ScannerPluginScanStatus.Completed
                    ? result.Status.ToString()
                    : result.Scan.Status.ToString();
                break;
            }
            ++published;
        }

        return new ScanRunExecution(
            new ScanRunOutcome(requested, published, lastStatus, lastScanStatus),
            failureName,
            previewPath);
    }
}
