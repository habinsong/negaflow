using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>
/// GrainMend 레이어 목록의 배선입니다. macOS <c>DefectLayerSection</c> 이 <c>AppModel</c> 의
/// 어느 함수를 부르는지에 대응하는 자리이며, 캔버스·검출·내보내기와 다른 이유로 바뀌므로
/// 여기 따로 둡니다.
/// </summary>
internal sealed class DevelopGrainMendLayers
{
    private readonly DevelopGrainMendPanel view;

    internal DevelopGrainMendLayers(DevelopGrainMendPanel view) => this.view = view;

    /// <summary>
    /// 목록을 다시 그립니다. 고른 사진이 바뀌거나, 항목이 늘거나 줄거나, 켜짐·강도가 바뀔 때
    /// 부릅니다.
    /// </summary>
    internal void Update()
    {
        if (view.DefectLayers is null || view.panel is null)
        {
            return;
        }
        view.panel.DefectLayers.ForgetMissingMaskPreview();
        LibraryFrameSnapshot? selectedFrame = view.panel.SelectedFrame;
        DefectLayerSectionState state = DefectLayerProjection.Create(
            view.panel.DefectLayers.PreviewFrame,
            DefectLayerTextFactory.Create(),
            view.panel.DefectLayers.MaskPreviewId,
            // macOS `libraryWorkflowTrackingState.defectReviewTracking` — 카탈로그에 적힌
            // 검토 완료 판입니다. 지금 recipe 와 세 값이 다르면 저절로 "아직"이 됩니다.
            Reviewed(selectedFrame),
            view.isRemovingDefects);
        view.DefectLayers.Update(
            selectedFrame?.Id,
            state,
            DefectLayerTextFactory.Create(),
            view.isRemovingDefects);
        ShowMaskOverlay();
    }

    internal void OnCommand(object? sender, DefectLayerCommandEventArgs args)
    {
        _ = sender;
        if (view.panel?.SelectedFrame is not { } selectedFrame ||
            !string.Equals(selectedFrame.Id, args.FrameId, StringComparison.Ordinal))
        {
            return;
        }
        switch (args.Command)
        {
            case DefectLayerCommand.ToggleEnabled:
                Apply(view.panel.DefectLayers.SetEnabled(args.Id, !IsLayerEnabled(args.Id)));
                break;
            case DefectLayerCommand.Delete:
                Apply(view.panel.DefectLayers.Remove(args.Id));
                break;
            case DefectLayerCommand.ToggleMask:
                view.panel.DefectLayers.ToggleMaskPreview(args.Id);
                Update();
                break;
            case DefectLayerCommand.SetStrength:
                SetLayerStrength(args);
                break;
            case DefectLayerCommand.MarkReviewed:
                // macOS `markDefectRecipeReviewed`. 현상 결과는 바뀌지 않으므로 미리보기를
                // 다시 걸지 않고 목록만 다시 그립니다.
                if (view.panel.MarkDefectRecipeReviewed() == LibraryFrameError.None)
                {
                    Update();
                }
                break;
            default:
                break;
        }
    }

    /// <summary>
    /// 끄는 동안에는 미리보기만 다시 그리고 목록은 건드리지 않습니다 — 목록을 다시 만들면
    /// 슬라이더가 새로 붙어 드래그가 끊깁니다. 놓을 때 한 번만 저장합니다.
    /// </summary>
    private void SetLayerStrength(DefectLayerCommandEventArgs args)
    {
        if (view.panel is null)
        {
            return;
        }
        LibraryFrameError error =
            view.panel.DefectLayers.SetStrength(args.Id, args.Strength, args.IsLive);
        if (error != LibraryFrameError.None)
        {
            // 저장 실패 전 EndGesture가 live 값과 cache를 지웠습니다. 목록과 화소도 같은
            // committed recipe로 즉시 되돌려 서로 다른 상태가 화면에 남지 않게 합니다.
            Update();
            view.RequestPreviewReplacingCurrent();
            return;
        }
        if (args.IsLive)
        {
            LibraryFrameSnapshot? selectedFrame = view.panel.SelectedFrame;
            view.DefectLayers.UpdateDoneState(DefectLayerProjection.Create(
                view.panel.DefectLayers.PreviewFrame,
                DefectLayerTextFactory.Create(),
                view.panel.DefectLayers.MaskPreviewId,
                Reviewed(selectedFrame),
                view.isRemovingDefects));
            view.RequestPreview();
            return;
        }
        Update();
        view.RequestDefectPreview();
    }

    /// <summary>
    /// 고른 레이어의 마스크를 캔버스에 덮습니다. 검토 중인 후보 덮개와 같은 <c>Image</c> 를
    /// 쓰므로, 검토가 진행 중이면 그쪽을 건드리지 않습니다 — 두 덮개가 한 자리를 다투면
    /// 나중 것만 보이고 사용자는 어느 쪽을 보고 있는지 알 수 없습니다.
    /// </summary>
    private void ShowMaskOverlay()
    {
        if (view.panel is null || view.canvas is null ||
            view.grainMend.PendingEdit is not null ||
            view.grainMend.IsDetecting ||
            view.grainMend.ActiveRegionKind is not null ||
            view.grainMend.Strokes.Tool != GrainMendTool.None)
        {
            return;
        }
        if (view.panel.DefectLayers.MaskPreviewId is not { } id ||
            view.panel.SelectedFrame is not { } frame ||
            view.canvas.PreviewBitmap is null ||
            view.panel.DefectLayers.Items.FirstOrDefault(item => item.Id == id) is not { } item)
        {
            view.review.HideOverlay();
            return;
        }

        int width = view.canvas.PreviewBitmap.PixelWidth;
        int height = view.canvas.PreviewBitmap.PixelHeight;
        double pointScale = view.canvas.TryGetPreviewFrame(out PreviewFrame displayFrame) &&
            displayFrame.Width > 0.0
                ? width / displayFrame.Width
                : 1.0;
        if (DefectMaskOverlayRenderer.Render(
                frame,
                width,
                height,
                item,
                pointScale) is not { } bgra)
        {
            view.review.HideOverlay();
            return;
        }
        view.canvas.ShowDefectPixels(bgra, width, height);
    }

    /// <summary>
    /// 카탈로그에 적힌 검토 완료 판입니다. 투영이 지금 recipe 와 대조해 완료 여부를 냅니다 —
    /// 여기서 대조하면 판정이 두 벌이 됩니다.
    /// </summary>
    private static DefectReviewMark? Reviewed(LibraryFrameSnapshot? frame) =>
        frame?.DefectReviewMark is { } mark
            ? new DefectReviewMark(
                mark.RecipeRevision,
                mark.RecipeSha256,
                mark.SourceIdentitySha256)
            : null;

    private bool IsLayerEnabled(Guid id) =>
        view.panel?.DefectLayers.Items.FirstOrDefault(item => item.Id == id)?.Enabled == true;

    private void Apply(LibraryFrameError error)
    {
        if (error != LibraryFrameError.None)
        {
            return;
        }
        // Update 가 끝에서 목록도 다시 그립니다.
        view.chrome.Update();
        view.RequestDefectPreview();
    }
}
