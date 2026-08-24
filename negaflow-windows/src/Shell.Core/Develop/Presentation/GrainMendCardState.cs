using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// GrainMend 카드가 한 번에 내는 상태입니다. 어느 단추가 눌리는지, 검토 줄이 보이는지,
/// 어느 캡슐이 켜진 것으로 보이는지를 모두 여기서 정합니다.
/// </summary>
public sealed record GrainMendCardState(
    bool AutoEnabled,
    bool GuidedEnabled,
    bool BrushEnabled,
    bool CloneEnabled,
    bool AutoResetEnabled,
    bool GuidedResetEnabled,
    bool BrushResetEnabled,
    bool CloneResetEnabled,
    bool Reviewing,
    bool SensitivityEnabled,
    bool MicroSpecksEnabled,
    bool RemoveEnabled,
    bool CancelEnabled,
    bool AutoActive,
    bool GuidedActive,
    bool BrushActive,
    bool CloneActive,
    bool ReviewingAutomatic);

/// <summary>
/// 카드가 무엇을 열고 닫는지 정하는 규칙입니다. 뷰 안에 있을 때는 창을 띄우지 않고 확인할 수
/// 없었고, 자동·가이드가 왜 눌리지 않는지도 코드로 물어볼 수 없었습니다.
/// </summary>
public static class GrainMendCardProjection
{
    /// <param name="hasFrame">고른 사진이 있는지.</param>
    /// <param name="pendingLabel">아직 받아들이지 않은 검출의 이름표. 없으면 검토 중이 아닙니다.</param>
    /// <param name="includedCount">검토에서 켜 둔 성분 수. 검토 세션이 없으면 null.</param>
    public static GrainMendCardState Create(
        bool hasFrame,
        bool isDetecting,
        DefectEditLabelKind? activeRegionKind,
        DefectEditLabelKind? pendingLabel,
        int? includedCount,
        GrainMendTool tool,
        bool hasAutomaticEdits,
        bool hasGuidedEdits,
        bool hasBrushEdits,
        bool hasCloneEdits)
    {
        bool reviewing = pendingLabel is not null;
        return new GrainMendCardState(
            // macOS action pill은 현재 모드를 취소하거나 다른 모드로 전환하는 입력이므로
            // 검출·검토 중에도 닫지 않습니다.
            AutoEnabled: hasFrame,
            GuidedEnabled: hasFrame,
            BrushEnabled: hasFrame,
            CloneEnabled: hasFrame,
            AutoResetEnabled: hasAutomaticEdits,
            GuidedResetEnabled: hasGuidedEdits,
            BrushResetEnabled: hasBrushEdits,
            CloneResetEnabled: hasCloneEdits,
            Reviewing: reviewing,
            SensitivityEnabled: reviewing && !isDetecting,
            MicroSpecksEnabled: reviewing && !isDetecting,
            // 모두 꺼 둔 검토를 받아들이면 아무것도 고치지 않는 항목이 남습니다.
            RemoveEnabled: reviewing && (includedCount ?? 1) > 0,
            CancelEnabled: reviewing,
            AutoActive: activeRegionKind == DefectEditLabelKind.Automatic,
            GuidedActive: activeRegionKind == DefectEditLabelKind.Guided,
            BrushActive: tool == GrainMendTool.Brush,
            CloneActive: tool == GrainMendTool.Clone,
            ReviewingAutomatic: pendingLabel == DefectEditLabelKind.Automatic);
    }
}
