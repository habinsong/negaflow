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
        // **승인된 플러그인은 배치 시작에서 한 번만 정합니다.**
        //
        // 앞 판은 회차마다 `approvedPlugin()` 을 불렀고, 그것은 `Plugins` 목록을 다시
        // 훑습니다. 그런데 `ScanSessionController.Refresh()` 가 배치 도중에도 돌 수 있고
        // (`ActiveGateway.Discover()` 로 디스크를 다시 읽습니다), 그 창에서 목록이 비면
        // 회차가 **스캔을 시도하지도 않고 조용히 끝났습니다** - 실기에서 프레임 셋 중
        // 마지막 한 장이 빠지는데 실패 기록이 한 줄도 없던 것이 이 모양입니다.
        //
        // 한 배치는 한 플러그인입니다. 도중에 바꿔 다는 것은 어차피 뜻이 없습니다.
        (InstalledScannerPlugin? batchPlugin, ScannerPluginTrustIdentity? batchIdentity) =
            approvedPlugin();
        ScannerDiagnosticsLog.Write(
            $"batch start preview={preview} requested={requested} " +
            $"plugin={batchPlugin?.Manifest.Id ?? "none"}");
        if (batchPlugin is null || batchIdentity is null)
        {
            ScannerDiagnosticsLog.Write("batch end published=0 reason=no approved plugin at start");
            return new ScanRunExecution(
                new ScanRunOutcome(requested, 0, null, null),
                ScannerPluginScanStatus.CapabilityMismatch.ToString(),
                null);
        }
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
            InstalledScannerPlugin plugin = batchPlugin;
            ScannerPluginTrustIdentity identity = batchIdentity;
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
                    // 사용자가 멈춘 것은 실패가 아닙니다. 이름을 남기지 않아야 화면이
                    // 조용합니다 - 앞 판은 취소도 `ProcessFailed` 로 접혀 빨간 줄이 떴습니다.
                    if (scanned.Status == ScannerPluginScanStatus.Cancelled)
                    {
                        stopReason = $"cancelled by the user at index={index}";
                        break;
                    }
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

            ScannerPluginLibraryScanResult result;
            try
            {
                result = await gateway
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
            }
            catch (OperationCanceledException)
            {
                stopReason = $"cancelled by the user at index={index}";
                break;
            }
            catch (Exception error)
            {
                // **배치가 조용히 사라지지 않게 합니다.** 실기에서 다섯 장을 청한 롤이 첫
                // 장만 게시하고 두 번째에서 없어졌는데, 파일은 스캔까지 끝났고 게시 줄도
                // 종료 줄도 남지 않았습니다 - 게시 도중 던진 예외가 여기까지 그대로 올라와
                // 루프 밖으로 나갔기 때문입니다(워커 스레드에서 XAML 을 건드린 COMException).
                // 그 자리는 따로 고쳤지만, 어떤 예외든 롤을 통째로 지우지 못하게 막습니다.
                failureName = error.GetType().Name;
                stopReason = $"publish threw at index={index}: {error.GetType().Name} {error.Message}";
                ScannerDiagnosticsLog.Write($"batch {stopReason}");
                break;
            }
            lastStatus = result.Status;
            lastScanStatus = result.Scan.Status;
            // IR 결과(`InfraredApplied` / `InfraredSkipped` / `InfraredSourceUnreadable`)는
            // `PublicationStatus` 가 전부 `Published` 로 뭉개므로 어디에도 안 남았습니다.
            // IR 을 켜 놓고도 적용이 안 되는 것을 화면에서 가릴 방법이 없었습니다.
            ScannerDiagnosticsLog.Write(
                $"batch frame index={index} scan={result.Scan.Status} " +
                $"publish={result.Publication?.Status.ToString() ?? "none"} " +
                $"ir={(result.Publication?.Frame?.InfraredPath is { Length: > 0 } ? "paired" : "none")} " +
                // **적용 실패 코드를 그대로 남깁니다.** `publish=Published` 하나로는
                // "IR 이 왜 안 붙었는가" 를 못 가립니다 - `NoDefects` 인지 `SourceMismatch`
                // 인지 `DetectionFailed` 인지에 따라 다음에 볼 자리가 완전히 다릅니다.
                $"irApply={result.Publication?.Infrared?.Status.ToString() ?? "none"} " +
                $"irRecipe={(result.Publication?.Infrared?.Recipe is null ? "none" : "written")} " +
                $"irSidecar={result.Publication?.Infrared?.SidecarError.ToString() ?? "none"} " +
                $"irCatalog={result.Publication?.Infrared?.CatalogError.ToString() ?? "none"} " +
                $"-> {result.Publication?.Frame?.Id ?? "none"}");
            if (!result.IsSuccess)
            {
                if (result.Scan.Status == ScannerPluginScanStatus.Cancelled)
                {
                    stopReason = $"cancelled by the user at index={index}";
                    break;
                }
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
