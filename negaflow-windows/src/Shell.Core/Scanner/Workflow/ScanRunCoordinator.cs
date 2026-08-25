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
        Action<int>? framePublished,
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
        // 배치가 **왜** 끝났는지를 남깁니다. 앞 판은 프레임 셋 중 마지막 한 장이 스캔되지
        // 않는데 실패 기록이 한 줄도 없었습니다 - 플러그인을 부르기 전에 멈추면 아무도
        // 아무 것도 적지 않았기 때문입니다. 그러면 추측밖에 할 수 없습니다.
        ScannerDiagnosticsLog.Write(
            $"batch start preview={preview} requested={requested}");
        string stopReason = "completed";
        for (int index = 0; index < requested; ++index)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                stopReason = $"cancelled at index={index}";
                ScannerDiagnosticsLog.Write($"batch {stopReason}");
            }
            cancellationToken.ThrowIfCancellationRequested();
            if (buildRequest(preview, destinationForIndex(index), index) is not { } request)
            {
                stopReason = $"no request at index={index} (device or capabilities missing)";
                break;
            }
            (InstalledScannerPlugin? plugin, ScannerPluginTrustIdentity? identity) = approvedPlugin();
            if (plugin is null || identity is null)
            {
                stopReason =
                    $"no approved plugin at index={index} " +
                    $"(plugin={plugin is not null} identity={identity is not null})";
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
                    stopReason = $"preview scan failed at index={index}: {failureName}";
                    break;
                }
                previewPath = scanned.ArtifactCommit?.Artifacts?.VisiblePath;
                if (previewPath is null)
                {
                    failureName = ScannerPluginScanStatus.ArtifactCommitFailed.ToString();
                    stopReason = $"preview artifact missing at index={index}";
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
                    stopReason = $"preview publish refused at index={index}: {failureName}";
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
            // IR 결과(`InfraredApplied` / `InfraredSkipped` / `InfraredSourceUnreadable`)는
            // `PublicationStatus` 가 전부 `Published` 로 뭉개므로 어디에도 안 남았습니다.
            // IR 을 켜 놓고도 적용이 안 되는 것을 화면에서 가릴 방법이 없었습니다.
            ScannerDiagnosticsLog.Write(
                $"batch frame index={index} scan={result.Scan.Status} " +
                $"publish={result.Publication?.Status.ToString() ?? "none"} " +
                $"ir={(result.Publication?.Frame?.InfraredPath is { Length: > 0 } ? "paired" : "none")} " +
                $"-> {result.Publication?.Frame?.Id ?? "none"}");
            if (!result.IsSuccess)
            {
                failureName = result.Scan.Status == ScannerPluginScanStatus.Completed
                    ? result.Status.ToString()
                    : result.Scan.Status.ToString();
                stopReason = $"scan failed at index={index}: {failureName}";
                break;
            }
            if (index == 0 && guidedCarryover is not null &&
                result.Publication?.Frame is { } publishedFrame)
            {
                guidedCarryoverPublished?.Invoke(publishedFrame.Id, guidedCarryover);
            }
            ++published;
            // **한 쌍이 끝날 때마다** 알립니다. 배치가 다 끝난 뒤에 한 번만 알리면, 프레임
            // 세 장짜리 롤에서 마지막 장이 끝날 때까지 아무 것도 안 보입니다 - macOS 는
            // 스캔한 장이 나오는 대로 보여 줍니다.
            framePublished?.Invoke(published);
        }

        ScannerDiagnosticsLog.Write(
            $"batch end published={published}/{requested} reason={stopReason}");
        return new ScanRunExecution(
            new ScanRunOutcome(requested, published, lastStatus, lastScanStatus),
            failureName,
            previewPath,
            previewFrameId,
            previewScanArea);
    }
}
