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
