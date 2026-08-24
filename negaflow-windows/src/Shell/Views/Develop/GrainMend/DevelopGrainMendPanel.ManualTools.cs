using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>Brush/Clone 진입과 다른 캔버스 도구의 상호 배제입니다.</summary>
public sealed partial class DevelopGrainMendPanel
{
    /// <summary>macOS <c>.brushDefectTool</c> — 켜져 있으면 끕니다.</summary>
    internal void ToggleBrushDefect() => ToggleManualTool(GrainMendTool.Brush);

    /// <summary>macOS <c>.cloneStampTool</c> — 켜져 있으면 끕니다.</summary>
    internal void ToggleCloneStamp() => ToggleManualTool(GrainMendTool.Clone);

    private void ToggleManualTool(GrainMendTool tool)
    {
        if (panel?.SelectedFrame is null)
        {
            return;
        }

        bool activating = grainMend.Strokes.Tool != tool;
        if (activating)
        {
            exitCompetingCanvasTools?.Invoke();
        }
        CancelRegionDefectSessionIfActive();
        if (activating)
        {
            // persistent layer mask와 Brush/Clone 초안은 같은 overlay 표면을 씁니다. 도구가
            // 소유권을 가져가기 전에 이전 mask만 한 번 닫고, 이후 chrome 갱신은 건드리지 않습니다.
            review.HideOverlay();
        }
        SetTool(activating ? tool : GrainMendTool.None);
        if (activating)
        {
            canvas?.FocusHost();
        }
    }

    private void CancelRegionDefectSessionIfActive()
    {
        if (grainMend.ActiveRegionKind is not null || isRemovingDefects)
        {
            CancelRegionDefectSession();
        }
    }

    internal void ShowDefectWriteError() =>
        SetStatus(AppResources.Get("libraryProcessApplyFailed", "Text"));
}
