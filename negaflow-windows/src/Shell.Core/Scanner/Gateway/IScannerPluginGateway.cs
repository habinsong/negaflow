using Negaflow.Catalog;

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

    /// <param name="isPreviewScan">
    /// 이 스캔을 프리뷰로 다루는지입니다. 전선의 <c>preview</c> 깃발과 다릅니다 - 평판
    /// 프리뷰는 해상도를 명시한 저해상도 본 스캔으로 나가므로 전선에서는 프리뷰가 아닙니다.
    /// 화면에 프리뷰로 띄울지는 부르는 쪽의 뜻이라 따로 받습니다.
    /// </param>
    Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        ImageTransformRecipe? initialTransform,
        bool isPreviewScan,
        CancellationToken cancellationToken);

    Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken);
}
