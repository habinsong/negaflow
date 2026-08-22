using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>작업공간 이름표입니다. 선택·레이아웃과 다른 이유입니다.</summary>
internal sealed class DevelopWorkspaceCopy
{
    private readonly DevelopWorkspaceView view;

    internal DevelopWorkspaceCopy(DevelopWorkspaceView view) => this.view = view;

    internal void Localize()
    {
        view.LeftPanel.Localize();
        string noFrame = AppResources.Get("noFrame", "Text");
        view.NoFrameLeftText.Text = noFrame;
        view.NoFrameInspectorText.Text = noFrame;
        view.DevelopHeaderText.Text = AppResources.Get("menuDevelop", "Text");
        view.InfoCards.Localize();
        view.Adjustments.Localize();
        view.BaseCard.Localize();
        view.GeometryCard.Localize();
        if (view.panel is not null)
        {
            view.GeometryCard.UpdateAspectControls(view.panel, view.crop.IsAspectLocked);
        }
        view.HistogramView.Localize(
            AppResources.Get("developHistogram", "Text"),
            AppResources.Get("developHistogramShadow", "Text"),
            AppResources.Get("developHistogramDensity", "Text"),
            AppResources.Get("developHistogramExposure", "Text"),
            AppResources.Get("developHistogramHighlight", "Text"),
            AppResources.Get("developHistogramRgb", "Text"),
            AppResources.Get("developHistogramClippingFormat", "Value"),
            AppResources.Get("developHistogramRedShort", "Text"),
            AppResources.Get("developHistogramGreenShort", "Text"),
            AppResources.Get("developHistogramBlueShort", "Text"),
            AppResources.Get("developHistogramKeyboardHelp", "Value"));
        string basic = AppResources.Get("developTabBasic", "Value");
        string baseTitle = AppResources.Get("developTabBase", "Value");
        string edit = AppResources.Get("developTabEdit", "Value");
        string defects = AppResources.Get("developTabDefects", "Value");
        string info = AppResources.Get("developTabInfo", "Value");
        string reset = AppResources.Get("developTabReset", "Value");
        SetLocalizedNameAndTooltip(view.BasicTabButton, basic);
        SetLocalizedNameAndTooltip(view.BaseTabButton, baseTitle);
        SetLocalizedNameAndTooltip(view.EditTabButton, edit);
        SetLocalizedNameAndTooltip(view.DefectsTabButton, defects);
        SetLocalizedNameAndTooltip(view.InfoTabButton, info);
        SetLocalizedNameAndTooltip(view.ResetTabButton, reset);
        view.PreviewCanvas.Localize();
        view.GrainMendPanel.Localize();
        // 아래 상태줄도 리소스 문구입니다 — 사슬에서 빠져 있었습니다.
        view.StatusBar.Localize();
        // 사진 이름("사진 %d")과 필름 종류("컬러 네거티브")는 **항목을 만들 때** 정해집니다.
        // 필름스트립·고름 상자는 그 항목을 그대로 보므로, 다시 만들지 않으면 언어를 바꿔도
        // 옛 언어로 남습니다.
        view.frames.Refresh();
    }

    private static void SetLocalizedNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
