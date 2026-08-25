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
                // `ConfigureAwait(false)` 를 쓰면 안 됩니다. 바로 아래
                // `library.PublishScannerPreviewFrame` 이 선택을 옮기고, 그 선택이
                // `WorkspacePresentationState.SetActiveFrame` -> 툴바 `SetWorkspaceSelection`
                // 까지 이어져 **XAML 속성을 건드립니다.** 워커 스레드에서 그것을 하면 WinUI 가
                // `COMException`(RPC_E_WRONG_THREAD)을 던지고, 그 예외가 프리뷰 게시를 통째로
                // 끊습니다 - 실제로 V700 프리뷰가 파일까지 다 만들고도 화면·썸네일·파일 목록
                // 어디에도 안 나오고, region 검출과 본 스캔도 시작되지 않았습니다.
                //
                // 본 스캔 경로(`ScannerScanPublisher.ScanAndPublishAsync`)는 같은 자리에서
                // `ConfigureAwait` 를 붙이지 않아 UI 컨텍스트를 유지합니다. 여기도 같게 둡니다.
                ScannerPluginScanResult scanned = await gateway
                    .ScanAsync(plugin, identity, request, cancellationToken);
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
