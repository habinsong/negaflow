using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>Auto/Guided region 도구의 활성화와 다른 캔버스 도구 배제입니다.</summary>
public sealed partial class DevelopGrainMendPanel
{
    private Action? exitCompetingCanvasTools;

    /// <summary>
    /// macOS <c>handleDevelopToolShortcutRequest</c> 의 <c>.autoDefectTool</c> — 모든 다른 캔버스
    /// interaction을 먼저 내리고, 같은 Auto면 취소하며 아니면 전체 프레임 검출을 시작합니다.
    /// </summary>
    internal Task RunAutoDefectAsync()
    {
        bool wasActive = grainMend.ActiveRegionKind == DefectEditLabelKind.Automatic;
        exitCompetingCanvasTools?.Invoke();
        CancelRegionDefectSession();
        SetTool(GrainMendTool.None);
        if (wasActive)
        {
            return Task.CompletedTask;
        }
        return detector.DetectAsync(
            new DefectRect(0.0, 0.0, 1.0, 1.0),
            automatic: true);
    }

    /// <summary>macOS <c>.guidedDefectTool</c> — 다른 도구를 내린 뒤 켜져 있으면 끕니다.</summary>
    internal void ToggleGuidedDefect()
    {
        bool wasActive = grainMend.ActiveRegionKind == DefectEditLabelKind.Guided;
        exitCompetingCanvasTools?.Invoke();
        CancelRegionDefectSession();
        SetTool(wasActive
            ? GrainMendTool.None
            : GrainMendTool.Guided);
        if (grainMend.Strokes.Tool == GrainMendTool.Guided)
        {
            canvas?.FocusHost();
        }
    }
}
