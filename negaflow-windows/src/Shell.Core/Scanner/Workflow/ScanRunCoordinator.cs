namespace Negaflow.Shell;

/// <param name="PreviewFrameId">
/// 백엔드가 프리뷰를 카탈로그 프레임으로 표현할 때의 선택적 식별자입니다. Windows의
/// 기본 프리뷰 경로는 카탈로그에 넣지 않고 파일만 남깁니다.
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
        CancellationToken cancellationToken)
    {
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
                // 프리뷰는 프레임 찾기용 임시 그림이라 카탈로그에 게시하지 않습니다. 파일은
                // 그대로 남겨 오버레이가 읽고, 평판 영역의 실제 자는 요청에서 보존합니다.
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
                previewScanArea = request.ScanArea;
                ++published;
                continue;
            }

            ScannerPluginLibraryScanResult result = await gateway
                .ScanAndPublishAsync(plugin, identity, request, library, false, cancellationToken)
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
            previewPath,
            previewFrameId,
            previewScanArea);
    }
}
