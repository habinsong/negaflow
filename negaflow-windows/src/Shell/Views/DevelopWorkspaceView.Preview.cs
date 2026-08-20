using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 미리보기 요청과 정착한 화소를 캔버스에 올리는 자리입니다.
/// </summary>
/// <remarks>
/// macOS <c>AppModel+DevelopRendering</c> 에 해당합니다 — 요청을 걸고, 늦게 온 결과를 버리고,
/// 정착한 그림을 썸네일로 넘깁니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    /// <summary>
    /// 현재 선택을 미리보기로 그립니다. 겹쳐 들어온 요청은 coordinator 가 합치되 마지막 것은
    /// 반드시 그리므로, 슬라이더를 끌어도 최종 상태가 화면에 남습니다.
    /// </summary>
    internal void RequestPreview() => RequestPreviewNow();

    internal void RequestPreviewNow()
    {
        // 레이어 강도를 끄는 동안에는 아직 저장하지 않은 값을 얹은 사본을 그립니다 — 저장은
        // 원본 파일 전체를 다시 해싱하므로 드래그 중에 하면 슬라이더가 멈춥니다.
        if (previewCoordinator is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            PreviewTrace.Write(
                "RequestPreviewNow skip coordinator=" + (previewCoordinator is not null) +
                " previewFrame=" + (panel?.DefectLayers.PreviewFrame is not null) +
                " selected=" + (panel?.SelectedFrame?.Id ?? "null"));
            return;
        }
        PreviewTrace.Write(
            "RequestPreviewNow frame=" + frame.Id +
            " path=" + frame.SourcePath +
            " presentedFrame=" + (presentedFrameId ?? "null"));
        // macOS `trimDeveloped(selectedFrameID:)` — 보고 있는 사진은 축출 대상에서 뺍니다.
        if (thumbnails is not null)
        {
            thumbnails.SelectedFrameId = frame.Id;
        }
        // macOS 는 프레임에 붙은 developedImage/thumbnail 을 고르는 즉시 그립니다.
        // 같은 사진의 슬라이더에서는 캐시를 올리지 않습니다 — 앞 판이 그 때문에
        // 끄는 동안 옛 그림을 덮었습니다.
        if (!string.Equals(presentedFrameId, frame.Id, StringComparison.Ordinal))
        {
            presentedFrameId = frame.Id;
            PreviewCanvas.HideCompareBefore();
            compareBeforeNeeded = false;
            compareBeforeInFlight = false;
            PreviewCanvas.SetCompareFrameOptions(CompareFrameOptions());
            // 360 JPEG 를 캔버스에 늘리면 깨진 채로 남습니다. 정착 현상본만 즉시 올리고,
            // 없으면 이전 그림을 유지한 채 새 렌더를 기다립니다.
            if (thumbnails is not null &&
                thumbnails.TryGetDeveloped(frame.Id, out var developed) &&
                Math.Max(developed.Width, developed.Height) >=
                    (int)DevelopPreviewProxy.FastPreviewMaxDimension)
            {
                PreviewTrace.Write(
                    "cache HIT frame=" + frame.Id +
                    " " + developed.Width + "x" + developed.Height +
                    " skipRequest=1");
                PreviewCanvas.Present(developed.Pixels, developed.Width, developed.Height);
                HistogramView.UpdatePixels(developed.Pixels, developed.Width, developed.Height);
                // 로그: HIT 직후 1536 인터랙티브를 다시 돌리면 3600 캐시를 덮어
                // 241–1147ms 동안 작게 보였습니다. 전환은 캐시만 올립니다.
                return;
            }
            PreviewTrace.Write(
                "cache MISS frame=" + frame.Id +
                " hasThumb=" + (thumbnails is not null));
        }
        _ = previewCoordinator.RequestAsync(frame, ShowPreview);
    }

    /// <summary>
    /// macOS <c>canvasDisplayTargetPixels</c> — 캔버스 긴 변 × DPI 배율입니다.
    /// </summary>
    private double DisplayTargetPixels()
    {
        double scale = PreviewCanvas.XamlRoot?.RasterizationScale ?? 1;
        if (scale <= 0)
        {
            scale = 1;
        }

        return Math.Max(PreviewCanvas.ActualWidth, PreviewCanvas.ActualHeight) * scale;
    }

    /// <summary>화면에 올라가 있는 그림의 리비전입니다.</summary>
    private int presentedRevision;

    private void ShowPreview(PreviewOutcome outcome)
    {
        // ☠️ **자기보다 오래된 그림은 버립니다.**
        //    배달은 UI 큐에 실리므로 두 장이 연달아 실릴 수 있고, 그러면 나중에 처리되는
        //    쪽이 더 옛 편집 상태일 수 있습니다. 실제로 그 때문에 노출을 올렸다 내리면
        //    내려간 그림이 화면에 안 남았습니다.
        string? expectedId = panel?.DefectLayers.PreviewFrame?.Id ?? panel?.SelectedFrame?.Id;
        PreviewTrace.Write(
            "ShowPreview kind=" + outcome.Kind +
            " frame=" + (outcome.FrameId ?? "null") +
            " expected=" + (expectedId ?? "null") +
            " rev=" + outcome.Revision +
            " presentedRev=" + presentedRevision +
            " w=" + outcome.Width +
            " h=" + outcome.Height +
            " pixels=" + (outcome.Pixels?.Length ?? 0) +
            " refuse=" + outcome.Refusal +
            " fault=" + (outcome.FaultMessage ?? "") +
            " fail=" + (outcome.Result?.FailureName ?? ""));
        if (outcome.FrameId is { Length: > 0 } frameId &&
            expectedId is { Length: > 0 } &&
            !string.Equals(frameId, expectedId, StringComparison.Ordinal))
        {
            PreviewTrace.Write("ShowPreview drop frame mismatch");
            return;
        }
        if (outcome.Revision != 0 && outcome.Revision < presentedRevision)
        {
            PreviewTrace.Write("ShowPreview drop old revision");
            return;
        }
        if (outcome.Revision > presentedRevision)
        {
            presentedRevision = outcome.Revision;
        }
        // 샘플러가 읽을 버퍼는 화면에 그린 것과 같아야 합니다 — 다른 것을 읽으면 보이는 색과
        // 적히는 수가 갈립니다.
        if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
            outcome.Pixels is not { } pixels ||
            outcome.Width == 0U ||
            outcome.Height == 0U)
        {
            // 취소는 이미 지나간 상태입니다. 마지막 그림을 지우면 스포이드 직후처럼
            // 겹친 요청이 빈 캔버스("이미지를 가져오세요")를 남깁니다.
            if (outcome.Kind == DevelopExportOutcomeKind.Cancelled)
            {
                return;
            }
            string reason = outcome.Kind == DevelopExportOutcomeKind.Completed
                ? $"{outcome.Result?.FailedStage} {outcome.Result?.FailureName}"
                : outcome.Kind == DevelopExportOutcomeKind.Faulted
                    ? outcome.FaultMessage ?? outcome.Kind.ToString()
                    : outcome.Refusal.ToString();
            ExportStatusText.Text =
                $"{AppResources.Get("developPreviewFailed", "Text")} ({reason})";
            // 고른 사진이 있는데 빈 캔버스("이미지를 가져오세요")를 띄우지 않습니다.
            // 실패한 배달이 자리표시자를 지워 선택이 안 먹은 것처럼 보였습니다.
            return;
        }
        PreviewCanvas.KeepPreviewPixels(pixels, outcome.Width, outcome.Height);

        int width = (int)outcome.Width;
        int height = (int)outcome.Height;
        PreviewCanvas.Present(pixels, width, height);
        HistogramView.UpdatePixels(pixels, width, height);
        // 방금 현상한 그림이 곧 라이브러리 카드의 썸네일입니다. 같은 픽셀을 두 번 만들지
        // 않으려고 여기서 넘깁니다.
        //
        // ☠️ **정착 패스에서만** 합니다. macOS 도 `ScanFrame.developedImage` 는 정착
        //    결과로만 채웁니다. 앞 판은 인터랙티브 패스에서도 했는데, 슬라이더를 끄는 동안
        //    한 칸마다 두 번씩 34.6MB 복사 + 866만 화소 축소를 **UI 스레드에서** 하느라
        //    슬라이더 자체가 멎었습니다.
        if (panel?.SelectedFrame is { } shown &&
            Math.Max(width, height) >= (int)DevelopPreviewProxy.FastPreviewMaxDimension)
        {
            // 정착 전에 다른 장으로 가도 인터랙티브(1536+)를 남기면 재방문이 HIT 입니다.
            // 12회 무작위 전환 로그에서 HIT 는 정착까지 기다린 2장뿐이었습니다.
            thumbnails?.RememberDeveloped(shown.Id, pixels, width, height);
            if (outcome.Settled)
            {
                thumbnails?.PublishFromDeveloped(shown.Id);
            }
            else
            {
                WarmNeighborDecodes(shown);
            }
        }

        if (panel is not null && outcome.Result is { Succeeded: true } applied)
        {
            panel.RememberAppliedBase(
                applied.AppliedDminRed,
                applied.AppliedDminGreen,
                applied.AppliedDminBlue);
            BaseCard.Sync();
        }

        crop.MarkPreviewReady();
        PreviewCanvas.RenderCropOverlay();
        PreviewCanvas.RefreshCompare();
        if (compareBeforeNeeded && !PreviewCanvas.HasCompareBefore)
        {
            RequestCompareBefore();
        }
    }
}
