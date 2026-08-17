using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>카드 이름·활성 캡슐·검토 줄 가시성입니다. 검출 실행과 다른 이유입니다.</summary>
internal sealed class DevelopGrainMendChrome
{
    private readonly DevelopGrainMendPanel view;

    internal DevelopGrainMendChrome(DevelopGrainMendPanel view) => this.view = view;

    internal void Update()
    {
        if (view.GrainMendAutoButton is null)
        {
            return;
        }
        view.GrainMendTitleText.Text = AppResources.Get("developGrainMend", "Text");
        view.GrainMendAutoText.Text = AppResources.Get("developGrainMendAuto", "Content");
        view.GrainMendGuidedText.Text = AppResources.Get("developGrainMendGuided", "Content");
        view.GrainMendBrushText.Text = AppResources.Get("developGrainMendBrush", "Content");
        view.GrainMendCloneText.Text = AppResources.Get("developGrainMendClone", "Content");
        SetLocalizedNameAndTooltip(
            view.GrainMendBrushButton, AppResources.Get("developGrainMendBrushHelp", "Value"));
        SetLocalizedNameAndTooltip(
            view.GrainMendCloneButton, AppResources.Get("developGrainMendCloneHelp", "Value"));
        SetLocalizedNameAndTooltip(
            view.GrainMendAutoButton, AppResources.Get("developGrainMendAutoHelp", "Value"));
        SetLocalizedNameAndTooltip(
            view.GrainMendGuidedButton,
            AppResources.Get("developGrainMendGuidedHelp", "Value"));
        GrainMendCardState card = GrainMendCardProjection.Create(
            view.panel?.SelectedFrame is not null,
            view.grainMend.IsDetecting,
            view.grainMend.PendingEdit?.Label.Kind,
            view.grainMend.PendingReview?.IncludedCount,
            view.grainMend.Strokes.Tool,
            view.panel?.HasDefectEdits(DefectEditLabelKind.Automatic) == true,
            view.panel?.HasDefectEdits(DefectEditLabelKind.Guided) == true,
            view.panel?.HasDefectEdits(DefectEditKind.Brush) == true,
            view.panel?.HasDefectEdits(DefectEditKind.Clone) == true);
        view.GrainMendAutoButton.IsEnabled = card.AutoEnabled;
        view.GrainMendAutoResetButton.IsEnabled = card.AutoResetEnabled;
        view.GrainMendGuidedButton.IsEnabled = card.GuidedEnabled;
        view.GrainMendGuidedResetButton.IsEnabled = card.GuidedResetEnabled;
        UpdateHud(card);

        string reset = AppResources.Get("developGrainMendReset", "Value");
        SetLocalizedNameAndTooltip(view.GrainMendAutoResetButton, reset);
        SetLocalizedNameAndTooltip(view.GrainMendGuidedResetButton, reset);
        SetLocalizedNameAndTooltip(view.GrainMendBrushResetButton, reset);
        SetLocalizedNameAndTooltip(view.GrainMendCloneResetButton, reset);

        view.GrainMendBrushButton.IsEnabled = card.BrushEnabled;
        view.GrainMendCloneButton.IsEnabled = card.CloneEnabled;
        view.GrainMendBrushResetButton.IsEnabled = card.BrushResetEnabled;
        view.GrainMendCloneResetButton.IsEnabled = card.CloneResetEnabled;

        ApplyPill(view.GrainMendAutoPill, view.GrainMendAutoButton, card.AutoActive);
        ApplyPill(view.GrainMendGuidedPill, view.GrainMendGuidedButton, card.GuidedActive);
        ApplyPill(view.GrainMendBrushPill, view.GrainMendBrushButton, card.BrushActive);
        ApplyPill(view.GrainMendClonePill, view.GrainMendCloneButton, card.CloneActive);
        // 카드가 바뀌는 모든 자리는 목록도 바뀌는 자리입니다. 열두 군데를 따로 부르면
        // 언젠가 한 군데가 빠지고 목록만 옛 값을 붙듭니다.
        view.layers.Update();
    }

    /// <summary>
    /// 캔버스 위 캡슐입니다. 카드가 바뀌는 자리는 캡슐도 바뀌는 자리이므로 같은 한 번에 냅니다.
    /// </summary>
    private void UpdateHud(GrainMendCardState card)
    {
        if (view.canvas?.GrainMendHud is not { } hud)
        {
            return;
        }
        // 검토 중이 아니면 캡슐이 남아 있는 것은 가이드를 켜 둔 때뿐이고, 가이드는 자동이
        // 아닙니다 — 두 모드는 민감도도 미세 입자도 나눠 씁니다.
        bool automatic = card.Reviewing && card.ReviewingAutomatic;
        hud.Update(
            GrainMendHudProjection.Create(
                view.panel?.SelectedFrame is not null,
                view.grainMend.IsDetecting,
                view.grainMend.PendingEdit?.Label.Kind,
                view.grainMend.PendingReview,
                view.grainMend.Strokes.Tool),
            view.options.GetSensitivity(automatic),
            view.options.GetMicroSpecks(automatic),
            view.isRemovingDefects,
            DefectLayerTextFactory.ClassNames());
        // macOS `CanvasHUDLayer`: 브러시 도구를 켜면 브러시 컨트롤 바가 섭니다.
        hud.UpdateBrushBar(
            view.grainMend.Strokes.Tool == GrainMendTool.Brush,
            view.grainMend.Strokes.BrushThickness,
            view.grainMend.Strokes.HasPaintedStrokes,
            card.BrushResetEnabled,
            view.isRemovingDefects);
        // macOS `CloneStampOverlay` 는 복제 도구를 켜면 자기 컨트롤 바를 냅니다.
        hud.UpdateCloneBar(
            view.grainMend.Strokes.Tool == GrainMendTool.Clone,
            view.grainMend.Strokes.CloneSourceAnchor is not null,
            view.grainMend.Strokes.CloneDiameterPixels,
            view.grainMend.Strokes.CloneHardness,
            card.CloneResetEnabled,
            view.isRemovingDefects);
    }

    /// <summary>
    /// macOS InspectorActionPill 의 켜짐 표시입니다. 캡슐 바탕과 낭독기 상태가 함께 바뀌어야
    /// 눈으로 보는 것과 읽어 주는 것이 어긋나지 않습니다.
    /// </summary>
    private static void ApplyPill(Border pill, Button action, bool isActive)
    {
        pill.Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            isActive ? "NegaflowSelectionBrush" : "NegaflowSubtleFillBrush"];
        AutomationProperties.SetItemStatus(
            action,
            AppResources.Get(isActive ? "selected" : "notSelected", "Value"));
    }

    private static void SetLocalizedNameAndTooltip(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
