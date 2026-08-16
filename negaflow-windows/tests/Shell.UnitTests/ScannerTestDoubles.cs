using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

internal sealed class ImmediateUiDispatcher : IUiDispatcher
    {
        public bool HasThreadAccess => true;

        public bool TryEnqueue(Action callback)
        {
            callback();
            return true;
        }
    }
internal sealed class FakeScannerGateway(string pluginDirectory) : IScannerPluginGateway
    {
        public int DetectCalls { get; private set; }

        public IReadOnlyList<InstalledScannerPlugin> Discover() =>
            ScannerPluginDiscovery.Discover(pluginDirectory);

        public Task<ScannerPluginDetectResult> DetectAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            CancellationToken cancellationToken)
        {
            ++DetectCalls;
            return Task.FromResult(new ScannerPluginDetectResult(
                new ScannerPluginProcessResult(
                    ScannerPluginProcessStatus.Succeeded,
                    0,
                    [],
                    string.Empty),
                [
                    new ScannerPluginDevice(
                        "genesys:libusb:001:002",
                        "Plustek OpticFilm 8100",
                        "Plustek",
                        "OpticFilm 8100",
                        "usb",
                        null,
                        null,
                        null,
                        null,
                        null),
                ],
                false));
        }

        public Task<ScannerPluginCapabilitiesResult> GetCapabilitiesAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginDevice device,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ScannerPluginCapabilitiesResult(
                new ScannerPluginProcessResult(
                    ScannerPluginProcessStatus.Succeeded,
                    0,
                    [],
                    string.Empty),
                new ScannerPluginCapabilities(
                    [75, 300, 600, 3600, 7200],
                    ["color", "gray", "lineart"],
                    [8, 16],
                    SupportsPreview: true,
                    SupportsTransparency: true,
                    SupportsInfrared: true,
                    SupportsMultiExposure: false,
                    SupportsScanArea: true,
                    SupportsPositionedScanArea: false,
                    ["tiff"],
                    "token"),
                false));

        public Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginScanRequest request,
            LibraryHostService library,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<ScannerPluginScanResult> ScanAsync(
            InstalledScannerPlugin plugin,
            ScannerPluginTrustIdentity approvedIdentity,
            ScannerPluginScanRequest request,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
