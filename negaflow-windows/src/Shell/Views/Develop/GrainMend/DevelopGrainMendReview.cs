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
    internal void AcceptPending()
    {
        if (view.panel is null || view.grainMend.PendingEdit is null)
        {
            return;
        }
        DefectEditItem? edit = view.grainMend.BuildAcceptedEdit();
        if (edit is null)
        {
            CancelPending();
            return;
        }
        ClearPending();
        if (view.panel.AcceptDefectRegion(edit) != LibraryFrameError.None)
        {
            view.SetStatus(AppResources.Get("developGrainMendDetectFailed", "Text"));
            return;
        }
        view.SetStatus(string.Empty);
        view.chrome.Update();
        view.RequestPreview();
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

    internal void HideOverlay() => view.canvas?.HideDefectOverlay();

    /// <summary>
    /// macOS <c>CloneStampOverlay.draw</c>: 소스 창 미리보기, 커서 원과 그 안의 소스 화소,
    /// 그리고 샘플 십자선을 캔버스에 올립니다. Alt 를 누르고 있으면 원 대신 십자선만 냅니다.
    /// </summary>
    internal void RenderCloneCursor()
    {
        if (view.panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            view.canvas?.PreviewBitmap is null)
        {
            return;
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
            return;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
    }

    /// <summary>
    /// macOS <c>BrushOverlay</c>: 모아 둔 칠과 진행 중인 획을 빨강으로 캔버스에 올립니다.
    /// 칠이 없으면 덮개를 내립니다.
    /// </summary>
    internal void RenderPaintOverlay()
    {
        if (view.panel?.SelectedFrame is not { } frame || view.canvas?.PreviewBitmap is null)
        {
            return;
        }
        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        if (GrainMendPaintOverlayRenderer.Render(
                frame,
                width,
                height,
                view.grainMend.Strokes.PaintedStrokes,
                view.grainMend.Strokes.InProgressStroke,
                view.grainMend.Strokes.BrushThickness) is not { } bgra)
        {
            HideOverlay();
            return;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
    }

    internal void ShowOverlay(DefectEditItem edit)
    {
        if (view.panel?.SelectedFrame is not { } frame || view.canvas?.PreviewBitmap is null)
        {
            return;
        }

        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        if (GrainMendOverlayRenderer.Render(
                frame,
                width,
                height,
                edit,
                view.grainMend.PendingReview) is not { } bgra)
        {
            return;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
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
        view.RequestPreview();
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
        view.RequestPreview();
    }
}
