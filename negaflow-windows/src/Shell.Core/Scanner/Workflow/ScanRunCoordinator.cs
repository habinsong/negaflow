using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <param name="PreviewFrameId">
/// 메모리에만 게시한 프리뷰 frame의 선택적 식별자입니다.
/// </param>
/// <param name="PreviewScanArea">
/// 프리뷰를 찍을 때 스캐너에 보낸 영역입니다. 프리뷰 안의 비율을 밀리미터로 되돌리는 자입니다.
/// </param>
internal sealed record ScanRunExecution(
    ScanRunOutcome Outcome,
    string? FailureName,
    string? PreviewPath,
    string? PreviewFrameId = null,
    ScannerPluginScanArea? PreviewScanArea = null);

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
        Func<int, ImageTransformRecipe?> initialTransformForIndex,
        GrainMendGuidedCarryover? guidedCarryover,
        Action<string, GrainMendGuidedCarryover>? guidedCarryoverPublished,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(initialTransformForIndex);
        int published = 0;
        string? failureName = null;
        string? previewPath = null;
        string? previewFrameId = null;
        ScannerPluginScanArea? previewScanArea = null;
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
                // 프리뷰는 영속 catalog에서 제외한 세션 frame으로 게시합니다. 파일은 그대로
                // 남겨 오버레이가 읽고, 평판 영역의 실제 자는 플러그인이 적용한 값으로 보존합니다.
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
                if (previewPath is null)
                {
                    failureName = ScannerPluginScanStatus.ArtifactCommitFailed.ToString();
                    break;
                }
                ScannerFramePublishResult previewPublished = library.PublishScannerPreviewFrame(
                    new ScannerFrameImport(previewPath, null, request.Process)
                    {
                        Rotation = request.Rotation,
                        IsPreviewScan = true,
                    });
                if (previewPublished.Frame is not { } previewFrame)
                {
                    failureName = previewPublished.Status.ToString();
                    break;
                }
                previewFrameId = previewFrame.Id;
                previewScanArea = scanned.AppliedScanArea ?? request.ScanArea;
                ++published;
                continue;
            }

            ScannerPluginLibraryScanResult result = await gateway
                .ScanAndPublishAsync(
                    plugin,
                    identity,
                    request,
                    library,
                    initialTransformForIndex(index) ??
                        (index == 0 ? guidedCarryover?.Transform : null),
                    false,
                    cancellationToken)
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
            if (index == 0 && guidedCarryover is not null &&
                result.Publication?.Frame is { } publishedFrame)
            {
                guidedCarryoverPublished?.Invoke(publishedFrame.Id, guidedCarryover);
            }
            ++published;
        }

        return new ScanRunExecution(
            new ScanRunOutcome(requested, published, lastStatus, lastScanStatus),
            failureName,
            previewPath,
            previewFrameId,
            previewScanArea);
    }
}
