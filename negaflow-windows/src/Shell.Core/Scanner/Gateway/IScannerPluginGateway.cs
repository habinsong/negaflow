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
        CancellationToken cancellationToken,
        Action<ScanProgressReport>? onProgress = null);

    /// <param name="onProgress">
    /// 스캔이 도는 동안 진행 줄을 받습니다. **프리뷰도 여기로 옵니다** — 프리뷰는 게시까지 한
    /// 번에 하는 <c>ScanAndPublishAsync</c> 가 아니라 이 길로 가므로, 여기에 달지 않으면
    /// 프리뷰만 진행률이 "연결 중 0%" 에 멈춘 채로 끝납니다.
    /// </param>
    Task<ScannerPluginScanResult> ScanAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        CancellationToken cancellationToken,
        Action<ScanProgressReport>? onProgress = null);
}
