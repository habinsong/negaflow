using Negaflow.Interop;

namespace Negaflow.Shell;

internal static class ScannerScanPublisher
{
    internal static async Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        InfraredDetectorParameters? infraredParameters,
        DevelopRun? run,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(library);
        ScannerPluginScanResult scan = await ScannerScanExecutor.ScanAsync(
            plugin,
            approvedIdentity,
            request,
            cancellationToken);
        if (scan.ArtifactCommit?.Artifacts is not { } artifacts)
        {
            return new(ScannerPluginLibraryScanStatus.ScanFailed, scan, null);
        }

        ScannerFramePublishResult published = library.PublishScannerFrame(
            new ScannerFrameImport(
                artifacts.VisiblePath,
                artifacts.InfraredPath,
                request.Process)
            {
                Rotation = request.Rotation,
            },
            infraredParameters,
            run);
        return new(
            published.Status == ScannerFramePublishStatus.CatalogWriteFailed
                ? ScannerPluginLibraryScanStatus.CatalogPublicationFailed
                : ScannerPluginLibraryScanStatus.Published,
            scan,
            published);
    }
}
