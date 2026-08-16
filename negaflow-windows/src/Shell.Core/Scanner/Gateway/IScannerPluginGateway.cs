namespace Negaflow.Shell;

public interface IScannerPluginGateway
{
    IReadOnlyList<InstalledScannerPlugin> Discover();

    Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken);

    Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken);

    Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        CancellationToken cancellationToken);

    Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken);
}
