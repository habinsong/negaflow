using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed class ScannerPluginGateway : IScannerPluginGateway
{
    private readonly string? pluginDirectory;

    public ScannerPluginGateway(string? pluginDirectory = null) =>
        this.pluginDirectory = pluginDirectory;

    public IReadOnlyList<InstalledScannerPlugin> Discover() =>
        ScannerPluginDiscovery.Discover(pluginDirectory);

    public Task<ScannerPluginDetectResult> DetectAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.DetectAsync(plugin, approvedIdentity, cancellationToken);

    public Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginDevice device,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.GetCapabilitiesAsync(
            plugin,
            approvedIdentity,
            device,
            cancellationToken);

    public Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        ImageTransformRecipe? initialTransform,
        bool isPreviewScan,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.ScanAndPublishAsync(
            plugin,
            approvedIdentity,
            request,
            library,
            initialTransform: initialTransform,
            isPreviewScan: isPreviewScan,
            cancellationToken: cancellationToken);

    public Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken) =>
        ScannerPluginClient.ScanAsync(plugin, approvedIdentity, request, cancellationToken);
}
