using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Microsoft.UI.Xaml.Media;

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
    /// <summary>
    /// 개발자 디버그 오버레이가 켜지거나 단계가 바뀌었습니다. 그 단계까지만 현상한 그림을
    /// 다시 그립니다 - macOS 도 같은 지점에서 debugPreviewImages 를 갈아 끼웁니다.
    /// </summary>
    internal void OnDebugStateChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (previewCoordinator is null)
        {
            return;
        }
        Negaflow.Shell.Develop.DevelopDebugState state = Adjustments.DebugState;
        previewCoordinator.DebugStage = state.OverlayEnabled ? state.Stage : null;
        RequestPreviewNow();
    }

    internal void RequestPreview() => RequestPreviewNow();

    internal void RequestPreviewReplacingCurrent() => RequestPreviewNow(replaceActive: true);

    internal void RequestPreviewNow(bool replaceActive = false)
    {
        // 사용자가 새 사진이나 새 보정 상태를 요청하면 백그라운드 이웃 예열보다 현재 화면이
        // 항상 먼저입니다. 실행 중 포인터는 워커가 반환 뒤 Dispose 합니다.
        System.Threading.Interlocked.Exchange(ref neighborWarmRun, null)?.Cancel();
        // 레이어 강도를 끄는 동안에는 아직 저장하지 않은 값을 얹은 사본을 그립니다 — 저장은
        // 원본 파일 전체를 다시 해싱하므로 드래그 중에 하면 슬라이더가 멈춥니다.
        if (previewCoordinator is null || panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            PreviewTrace.Write(
                "RequestPreviewNow skip coordinator=" + (previewCoordinator is not null) +
                " previewFrame=" + (panel?.DefectLayers.PreviewFrame is not null) +
                " selected=" + (panel?.SelectedFrame?.Id ?? "null"));
            if (panel?.DefectLayers.PreviewFrame is { } refusedFrame)
            {
                GrainMendPanel.CompleteDefectPreview(refusedFrame);
            }
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
            // 360 JPEG 를 캔버스에 늘리면 깨진 채로 남습니다. interactive developed 프록시는
            // 즉시 올리되 정착본으로 오인하지 않고 native 요청을 계속합니다.
            bool canUseDevelopedCache =
                previewCoordinator.SoftProof is not { IsEnabled: true } &&
                !previewCoordinator.ClippingOverlayEnabled &&
                !previewCoordinator.UninvertedSource;
            if (canUseDevelopedCache && thumbnails is not null &&
                thumbnails.TryGetDeveloped(frame, out var developed) &&
                Math.Max(developed.Width, developed.Height) >=
                    (int)DevelopPreviewProxy.FastPreviewMaxDimension)
            {
                PreviewTrace.Write(
                    (developed.Settled ? "cache HIT frame=" : "cache PROXY frame=") + frame.Id +
                    " " + developed.Width + "x" + developed.Height +
                    " skipRequest=" + (developed.Settled ? "1" : "0"));
                PreviewCanvas.Present(developed.Pixels, developed.Width, developed.Height);
                GrainMendPanel.CompleteDefectPreview(frame);
                GrainMendPanel.TraceDevelopedPresentation(
                    frame,
                    developed.Width,
                    developed.Height);
                TraceInfraredPresentation(
                    frame.Id,
                    developed.Width,
                    developed.Height);
                TraceCompositionFrame(
                    frame.Id,
                    revision: 0,
                    settled: developed.Settled,
                    developed.Width,
                    developed.Height,
                    source: "cache");
                HistogramView.UpdatePixels(developed.Pixels, developed.Width, developed.Height);
                if (developed.Settled)
                {
                    // 로그: 정착 HIT 직후 1536 interactive를 다시 돌리면 3600 캐시를 덮어
                    // 241–1147ms 동안 작게 보였습니다. 정착본은 캐시만 올립니다.
                    WarmNeighborSettledPreviews(frame);
                    return;
                }
            }
            else
            {
                PreviewTrace.Write(
                    "cache MISS frame=" + frame.Id +
                    " hasThumb=" + (thumbnails is not null));
            }
        }
        _ = replaceActive
            ? previewCoordinator.RequestReplacingAsync(
                frame,
                outcome => ShowPreview(outcome, clearPixelsOnFailure: true, frame))
            : previewCoordinator.RequestAsync(
                frame,
                outcome => ShowPreview(outcome, clearPixelsOnFailure: false, frame));
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

    private void ShowPreview(
        PreviewOutcome outcome,
        bool clearPixelsOnFailure,
        LibraryFrameSnapshot requestedFrame)
    {
        // **자기보다 오래된 그림은 버립니다.**
        // 배달은 UI 큐에 실리므로 두 장이 연달아 실릴 수 있고, 그러면 나중에 처리되는
        // 쪽이 더 옛 편집 상태일 수 있습니다. 실제로 그 때문에 노출을 올렸다 내리면
        // 내려간 그림이 화면에 안 남았습니다.
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
            GrainMendPanel.CancelDevelopedPresentation(requestedFrame);
            return;
        }
        if (outcome.Revision != 0 && outcome.Revision < presentedRevision)
        {
            PreviewTrace.Write("ShowPreview drop old revision");
            GrainMendPanel.CancelDevelopedPresentation(requestedFrame);
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
                GrainMendPanel.CancelDevelopedPresentation(requestedFrame);
                return;
            }
            string reason = outcome.Kind == DevelopExportOutcomeKind.Completed
                ? $"{outcome.Result?.FailedStage} {outcome.Result?.FailureName}"
                : outcome.Kind == DevelopExportOutcomeKind.Faulted
                    ? outcome.FaultMessage ?? outcome.Kind.ToString()
                    : outcome.Refusal.ToString();
            ExportStatusText.Text =
                $"{AppResources.Get("developPreviewFailed", "Text")} ({reason})";
            if (clearPixelsOnFailure)
            {
                PreviewCanvas.KeepPreviewPixels(null, 0U, 0U);
                PreviewCanvas.ShowEmpty();
                HistogramView.Clear();
            }
            // 일반 실패는 고른 사진의 마지막 그림을 보존합니다. 저장 실패 rollback만은 마지막
            // 그림이 미확정 live 화소일 수 있으므로 위에서 fail-closed로 비웁니다.
            GrainMendPanel.CompleteDefectPreview(requestedFrame);
            GrainMendPanel.CancelDevelopedPresentation(requestedFrame);
            return;
        }
        PreviewCanvas.KeepPreviewPixels(pixels, outcome.Width, outcome.Height);

        int width = (int)outcome.Width;
        int height = (int)outcome.Height;
        if (PreviewTrace.IsEnabled)
        {
            PreviewTrace.Write(
                $"shown.develop {outcome.FrameId} {width}x{height} settled={outcome.Settled} " +
                Negaflow.Shell.Develop.PreviewPixelStats.Describe(pixels, width, height));
        }
        PreviewCanvas.Present(pixels, width, height);
        GrainMendPanel.CompleteDefectPreview(requestedFrame);
        GrainMendPanel.TraceDevelopedPresentation(requestedFrame, width, height);
        TraceInfraredPresentation(
            outcome.FrameId ?? expectedId ?? "null",
            width,
            height);
        TraceCompositionFrame(
            outcome.FrameId ?? expectedId ?? "null",
            outcome.Revision,
            outcome.Settled,
            width,
            height,
            source: "native");
        HistogramView.UpdatePixels(pixels, width, height);
        // 방금 현상한 그림이 곧 라이브러리 카드의 썸네일입니다. 같은 픽셀을 두 번 만들지
        // 않으려고 여기서 넘깁니다.
        //
        // **정착 패스에서만** 합니다. macOS 도 `ScanFrame.developedImage` 는 정착
        // 결과로만 채웁니다. 앞 판은 인터랙티브 패스에서도 했는데, 슬라이더를 끄는 동안
        // 한 칸마다 두 번씩 34.6MB 복사 + 866만 화소 축소를 **UI 스레드에서** 하느라
        // 슬라이더 자체가 멎었습니다.
        if (panel?.SelectedFrame is { } shown &&
            outcome.CacheIdentity is not null &&
            Math.Max(width, height) >= (int)DevelopPreviewProxy.FastPreviewMaxDimension)
        {
            // 정착 전에 다른 장으로 가도 인터랙티브(1536+)를 남기면 재방문이 HIT 입니다.
            // 12회 무작위 전환 로그에서 HIT 는 정착까지 기다린 2장뿐이었습니다.
            thumbnails?.RememberDeveloped(
                shown,
                pixels,
                width,
                height,
                outcome.Settled,
                outcome.CacheIdentity);
            if (outcome.Settled)
            {
                thumbnails?.PublishFromDeveloped(shown.Id);
                WarmNeighborSettledPreviews(shown);
            }
        }

        if (panel is not null && outcome.Result is { Succeeded: true } applied)
        {
            panel.RememberAppliedBase(
                applied.AppliedDminRed,
                applied.AppliedDminGreen,
                applied.AppliedDminBlue);
            BaseCard.Sync();
            // 개발자 디버그 구역에 이번 현상이 실제로 잰 값을 적습니다.
            Adjustments.ShowDebugMetrics(
                panel.LastAppliedBase,
                applied.DebugMetrics,
                (int)applied.ImageWidth,
                (int)applied.ImageHeight);
        }

        crop.MarkPreviewReady();
        // 새 미리보기(특히 90도 회전)는 크롭도 따라가야 합니다. 이후 줌·팬 동안에는
        // 이 프레임을 고정해 표시와 히트테스트가 같은 좌표계를 쓰게 합니다.
        PreviewCanvas.RenderCropOverlay(refreshFrame: true);
        // 평판 프리뷰를 보고 있으면 프레임 사각형도 새 그림 위에 다시 폅니다.
        SyncFlatbedOverlay();
        PreviewCanvas.RefreshCompare();
        if (compareBeforeNeeded && !PreviewCanvas.HasCompareBefore)
        {
            RequestCompareBefore();
        }
    }

    /// <summary>
    /// WriteableBitmap 복사·Invalidate 반환과 그 다음 WinUI 렌더 프레임을 분리해 기록합니다.
    /// <see cref="CompositionTarget.Rendering"/>은 물리 화면 스캔아웃 완료 증거가 아닙니다.
    /// </summary>
    private static void TraceCompositionFrame(
        string frameId,
        int revision,
        bool settled,
        int width,
        int height,
        string source)
    {
        PreviewTrace.Write(
            "Present submitted frame=" + frameId +
            " rev=" + revision +
            " settled=" + settled +
            " w=" + width +
            " h=" + height +
            " source=" + source);
        EventHandler<object>? handler = null;
        handler = (_, _) =>
        {
            if (handler is not null)
            {
                CompositionTarget.Rendering -= handler;
            }
            PreviewTrace.Write(
                "Composition frame frame=" + frameId +
                " rev=" + revision +
                " settled=" + settled +
                " w=" + width +
                " h=" + height +
                " source=" + source);
        };
        CompositionTarget.Rendering += handler;
    }
}
