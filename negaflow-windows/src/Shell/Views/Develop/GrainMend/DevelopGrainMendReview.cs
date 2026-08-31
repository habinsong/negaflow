using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>검토 확정·취소와 미리보기 덮개입니다. 검출 실행과 다른 이유입니다.</summary>
internal sealed class DevelopGrainMendReview
{
    private readonly DevelopGrainMendPanel view;

    internal DevelopGrainMendReview(DevelopGrainMendPanel view) => this.view = view;

    /// <summary>검토 중인 검출을 받아들여 recipe 에 담습니다.</summary>
    internal async Task AcceptPendingAsync()
    {
        if (view.panel is not { } panel || view.grainMend.PendingEdit is null ||
            view.isRemovingDefects)
        {
            return;
        }
        if (view.grainMend.CaptureAcceptance() is not { } acceptance ||
            panel.GrainMendFrameSnapshot(acceptance.DetectionToken.FrameId) is not { } startFrame)
        {
            view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
            view.chrome.Update();
            return;
        }

        view.removingAcceptance = acceptance;
        view.chrome.Update();
        try
        {
            GrainMendAcceptanceBuildResult built = await acceptance.BuildAsync(startFrame);
            if (!view.grainMend.OwnsAcceptance(acceptance))
            {
                return;
            }
            if (built.Kind == GrainMendAcceptanceBuildKind.Stale)
            {
                DiscardStale(acceptance);
                return;
            }
            if (built.Kind == GrainMendAcceptanceBuildKind.Failed)
            {
                view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
                return;
            }
            if (built.Edit is not { } edit)
            {
                CancelPending();
                return;
            }

            if (panel.GrainMendFrameSnapshot(
                    acceptance.DetectionToken.FrameId) is not { } currentFrame ||
                !await acceptance.DetectionToken.MatchesRecipeAsync(currentFrame) ||
                !view.grainMend.OwnsAcceptance(acceptance) ||
                !ReferenceEquals(
                    panel.GrainMendFrameSnapshot(acceptance.DetectionToken.FrameId),
                    currentFrame))
            {
                DiscardStale(acceptance);
                return;
            }

            if (view.grainMend.CommitAcceptedEdit(
                    edit,
                    item => panel.AcceptDefectRegion(
                        item,
                        acceptance.DetectionToken,
                        currentFrame)) != LibraryFrameError.None)
            {
                view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
                return;
            }
            HideOverlay();
            view.SetStatus(string.Empty);
            view.RequestDefectPreview();
        }
        finally
        {
            if (ReferenceEquals(view.removingAcceptance, acceptance))
            {
                view.removingAcceptance = null;
            }
            view.chrome.Update();
        }
    }

    private void DiscardStale(GrainMendAcceptance acceptance)
    {
        if (!view.grainMend.OwnsAcceptance(acceptance))
        {
            return;
        }
        ClearPending();
        view.SetStatus(string.Empty);
    }

    internal void CancelPending()
    {
        ClearPending();
        view.SetStatus(string.Empty);
        view.chrome.Update();
    }

    internal void ClearPending()
    {
        view.grainMend.ClearPending();
        HideOverlay();
    }

    internal void RestorePendingOverlay()
    {
        if (view.grainMend.PendingEdit is { } edit)
        {
            ShowOverlay(edit);
        }
        else
        {
            HideOverlay();
        }
    }

    internal void HideOverlay() => view.canvas?.HideDefectOverlay();

    /// <summary>
    /// macOS <c>CloneStampOverlay.draw</c>: 소스 창 미리보기, 커서 원과 그 안의 소스 화소,
    /// 그리고 샘플 십자선을 캔버스에 올립니다. Alt 를 누르고 있으면 원 대신 십자선만 냅니다.
    /// </summary>
    internal bool RenderCloneCursor()
    {
        if (view.panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            view.canvas?.PreviewBitmap is null)
        {
            return false;
        }
        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        double diameter = CloneStampCursorRenderer.ScreenDiameter(
            view.grainMend.Strokes.CloneDiameterPixels,
            width,
            metadata.PixelWidth);
        if (CloneStampCursorRenderer.Render(
                frame,
                width,
                height,
                view.canvas.PreviewPixels,
                view.input.CloneCursor,
                view.grainMend.Strokes.InProgressStroke,
                view.grainMend.Strokes.CloneSourceAnchor,
                view.grainMend.Strokes.CloneAlignedRawOffset,
                diameter,
                view.input.CloneSourceModifierDown) is not { } bgra)
        {
            HideOverlay();
            return false;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
        return true;
    }

    /// <summary>
    /// macOS <c>BrushOverlay</c>: 모아 둔 칠과 진행 중인 획을 빨강으로 캔버스에 올립니다.
    /// 칠이 없으면 덮개를 내립니다.
    /// </summary>
    internal bool RenderPaintOverlay()
    {
        if (view.panel?.SelectedFrame is not { } frame || view.canvas?.PreviewBitmap is null)
        {
            return false;
        }
        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        if (GrainMendPaintOverlayRenderer.Render(
                width,
                height,
                view.grainMend.Strokes.PaintedStrokes,
                view.grainMend.Strokes.InProgressStroke,
                view.grainMend.Strokes.BrushThickness) is not { } bgra)
        {
            HideOverlay();
            return false;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
        return true;
    }

    internal bool ShowOverlay(DefectEditItem edit)
    {
        if (view.panel?.SelectedFrame is not { } frame || view.canvas?.PreviewBitmap is null)
        {
            return false;
        }

        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        double pointScale = view.canvas.TryGetPreviewFrame(out PreviewFrame displayFrame) &&
            displayFrame.Width > 0.0
                ? width / displayFrame.Width
                : 1.0;
        if (GrainMendOverlayRenderer.Render(
                frame,
                width,
                height,
                edit,
                view.grainMend.PendingReview,
                pointScale) is not { } bgra)
        {
            return false;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
        return true;
    }

    internal void RemoveEdits(DefectEditKind kind)
    {
        if (view.panel is null)
        {
            return;
        }
        view.SetTool(GrainMendTool.None);
        if (view.panel.RemoveDefectEdits(kind) != LibraryFrameError.None)
        {
            return;
        }
        view.chrome.Update();
        view.RequestDefectPreview();
    }

    internal void RemoveEdits(DefectEditLabelKind label)
    {
        if (view.panel is null)
        {
            return;
        }
        view.SetTool(GrainMendTool.None);
        if (view.panel.RemoveDefectEdits(label) != LibraryFrameError.None)
        {
            return;
        }
        view.chrome.Update();
        view.RequestDefectPreview();
    }

    /// <summary>Brush HUD 초기화: 모드와 draft는 유지하고 IR 외 적용 결함만 지웁니다.</summary>
    internal void RemoveAppliedDefects()
    {
        if (view.panel is null ||
            view.panel.RemoveNonInfraredDefectEdits() != LibraryFrameError.None)
        {
            return;
        }
        view.chrome.Update();
        view.RequestDefectPreview();
    }
}
