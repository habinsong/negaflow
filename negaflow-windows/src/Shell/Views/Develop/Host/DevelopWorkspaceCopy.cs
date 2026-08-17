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
    }

    private static void SetLocalizedNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
