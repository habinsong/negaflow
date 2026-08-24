using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

internal static class ScannerScanPublisher
{
    internal static async Task<ScannerPluginLibraryScanResult> ScanAndPublishAsync(
        InstalledScannerPlugin plugin,
        ScannerPluginTrustIdentity approvedIdentity,
        ScannerPluginScanRequest request,
        LibraryHostService library,
        ImageTransformRecipe? initialTransform,
        InfraredDetectorParameters? infraredParameters,
        DevelopRun? run,
        bool isPreviewScan,
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
                // 프리뷰는 IR 을 함께 쓰지 않습니다. macOS 도 `preview ? nil : ...` 입니다.
                //
                // 판단은 `request.Preview` 가 아니라 부르는 쪽의 뜻입니다. 평판 프리뷰는
                // 전선에서 해상도를 명시한 저해상도 **본 스캔**으로 나가므로
                // `request.Preview` 가 거짓입니다(ScanOptionPolicy 의 `Preview: dpi == 0`).
                isPreviewScan ? null : artifacts.InfraredPath,
                request.Process)
            {
                Rotation = request.Rotation,
                InitialTransform = initialTransform,
                IsPreviewScan = isPreviewScan,
            },
            // 프리뷰에는 IR 결함 검출을 걸지 않습니다.
            isPreviewScan ? null : infraredParameters,
            run);
        return new(
            PublicationStatus(published),
            scan,
            published);
    }

    internal static ScannerPluginLibraryScanStatus PublicationStatus(
        ScannerFramePublishResult published) =>
        published.Status is ScannerFramePublishStatus.ReceiptWriteFailed or
            ScannerFramePublishStatus.CatalogWriteFailed
            ? ScannerPluginLibraryScanStatus.CatalogPublicationFailed
            : ScannerPluginLibraryScanStatus.Published;
}
