using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// GrainMend 카드가 무엇을 열고 닫는지입니다. 이 규칙이 뷰 안에 있을 때는 자동·가이드가 왜
/// 눌리지 않는지 창을 띄우지 않고는 물어볼 수 없었습니다.
/// </summary>
internal static class GrainMendCardProjectionTests
{
    public static void Run()
    {
        VerifyIdleCard();
        VerifyNoFrame();
        VerifyDetecting();
        VerifyReviewing();
        VerifyToolHighlighting();
    }

    private static GrainMendCardState Card(
        bool hasFrame = true,
        bool isDetecting = false,
        DefectEditLabelKind? pendingLabel = null,
        int? includedCount = null,
        GrainMendTool tool = GrainMendTool.None,
        bool hasAutomaticEdits = false,
        bool hasGuidedEdits = false,
        bool hasBrushEdits = false,
        bool hasCloneEdits = false) =>
        GrainMendCardProjection.Create(
            hasFrame,
            isDetecting,
            pendingLabel,
            includedCount,
            tool,
            hasAutomaticEdits,
            hasGuidedEdits,
            hasBrushEdits,
            hasCloneEdits);

    private static void VerifyIdleCard()
    {
        GrainMendCardState idle = Card();
        Check(idle.AutoEnabled && idle.GuidedEnabled && idle.BrushEnabled && idle.CloneEnabled,
            "grain_mend_card_offers_every_tool_on_a_selected_frame");
        // 검토 줄은 검출 결과가 있을 때만 나옵니다.
        Check(!idle.Reviewing && !idle.SensitivityEnabled && !idle.MicroSpecksEnabled &&
            !idle.RemoveEnabled && !idle.CancelEnabled,
            "grain_mend_card_hides_the_review_row_when_idle");
        Check(!idle.AutoResetEnabled && !idle.GuidedResetEnabled &&
            !idle.BrushResetEnabled && !idle.CloneResetEnabled,
            "grain_mend_card_has_nothing_to_reset_without_edits");
        GrainMendCardState withEdits = Card(
            hasAutomaticEdits: true, hasGuidedEdits: true, hasBrushEdits: true, hasCloneEdits: true);
        Check(withEdits.AutoResetEnabled && withEdits.GuidedResetEnabled &&
            withEdits.BrushResetEnabled && withEdits.CloneResetEnabled,
            "grain_mend_card_enables_each_reset_from_its_own_edits");
    }

    private static void VerifyNoFrame()
    {
        GrainMendCardState none = Card(hasFrame: false);
        Check(!none.AutoEnabled && !none.GuidedEnabled && !none.BrushEnabled && !none.CloneEnabled,
            "grain_mend_card_closes_every_tool_without_a_frame");
    }

    private static void VerifyDetecting()
    {
        GrainMendCardState busy = Card(isDetecting: true);
        // 검출이 도는 동안 또 시작하면 두 결과가 같은 자리를 두고 다툽니다.
        Check(!busy.AutoEnabled && !busy.GuidedEnabled,
            "grain_mend_card_refuses_a_second_detect_while_one_runs");
        Check(busy.BrushEnabled && busy.CloneEnabled,
            "grain_mend_card_keeps_the_direct_tools_during_detect");
    }

    private static void VerifyReviewing()
    {
        GrainMendCardState reviewing =
            Card(pendingLabel: DefectEditLabelKind.Automatic, includedCount: 411);
        Check(reviewing.Reviewing && reviewing.SensitivityEnabled &&
            reviewing.MicroSpecksEnabled && reviewing.CancelEnabled,
            "grain_mend_card_opens_the_review_row_for_a_pending_edit");
        // 검토 중에는 새 검출을 시작하지 않습니다 — 이것이 자동·가이드가 잠기는 유일한 이유입니다.
        Check(!reviewing.AutoEnabled && !reviewing.GuidedEnabled,
            "grain_mend_card_locks_detect_while_a_review_is_open");
        Check(reviewing.RemoveEnabled,
            "grain_mend_card_allows_removing_an_included_review");
        // 모두 꺼 둔 검토를 받아들이면 아무것도 고치지 않는 항목이 남습니다.
        Check(!Card(pendingLabel: DefectEditLabelKind.Guided, includedCount: 0).RemoveEnabled,
            "grain_mend_card_refuses_an_empty_review");
        // 검토 세션이 없는 검출도 받아들일 수 있어야 합니다.
        Check(Card(pendingLabel: DefectEditLabelKind.Guided, includedCount: null).RemoveEnabled,
            "grain_mend_card_allows_a_review_without_components");
        Check(reviewing.ReviewingAutomatic &&
            !Card(pendingLabel: DefectEditLabelKind.Guided, includedCount: 1).ReviewingAutomatic,
            "grain_mend_card_tells_automatic_and_guided_reviews_apart");
        // 검출 중에는 민감도를 다시 끌지 못합니다.
        Check(!Card(pendingLabel: DefectEditLabelKind.Automatic, includedCount: 1, isDetecting: true)
                .SensitivityEnabled,
            "grain_mend_card_locks_sensitivity_while_redetecting");
    }

    private static void VerifyToolHighlighting()
    {
        Check(Card(tool: GrainMendTool.Brush) is { BrushActive: true, CloneActive: false, GuidedActive: false },
            "grain_mend_card_highlights_the_brush");
        Check(Card(tool: GrainMendTool.Clone).CloneActive, "grain_mend_card_highlights_the_clone");
        Check(Card(tool: GrainMendTool.Guided).GuidedActive, "grain_mend_card_highlights_the_guide");
        // 자동은 도구가 아니라 검토 중인 검출로 켜짐을 표시합니다.
        Check(!Card(tool: GrainMendTool.Guided).AutoActive &&
            Card(pendingLabel: DefectEditLabelKind.Automatic, includedCount: 1).AutoActive,
            "grain_mend_card_highlights_auto_from_its_pending_detection");
    }
}
