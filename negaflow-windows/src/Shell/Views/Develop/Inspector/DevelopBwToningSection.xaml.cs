using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 흑백 토닝입니다. macOS 는 흑백 필름에서만 이 섹션을 냅니다.
/// </summary>
public sealed partial class DevelopBwToningSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopBwToningSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? RefreshRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            BwToningSection,
            BwToningHeaderButton,
            BwToningSectionTitleText,
            BwToningResetButton,
            AppResources.Get("developSectionBwToning", "Text"));
        BwToningModeLabel.Text = AppResources.Get("developBwToningMode", "Text");
        BwToningOffItem.Content = AppResources.Get("developBwToningOff", "Content");
        BwToningSeleniumItem.Content = AppResources.Get("developBwToningSelenium", "Content");
        BwToningSepiaItem.Content = AppResources.Get("developBwToningSepia", "Content");
        BwToningStrengthControl.Label = AppResources.Get("developBwToningStrength", "Text");
        BwToningShadowHueControl.Label = AppResources.Get("developBwToningShadowHue", "Text");
        BwToningHighlightHueControl.Label =
            AppResources.Get("developBwToningHighlightHue", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        BwToningRecipe bwToning = hostPanel.Color.BwToning;
        // macOS 는 흑백 필름에서만 이 섹션을 냅니다.
        Visibility = hostPanel.Color.ShowsBwToning
            ? Visibility.Visible
            : Visibility.Collapsed;
        isSynchronizing = true;
        try
        {
            BwToningModeSelector.SelectedIndex = bwToning.Mode switch
            {
                Catalog.BwToningMode.Selenium => 1,
                Catalog.BwToningMode.Sepia => 2,
                _ => 0,
            };
            // 끈 상태에서는 세기와 색조가 뜻이 없어 macOS 도 자리째 감춥니다.
            BwToningTintControls.Visibility = bwToning.Mode == Catalog.BwToningMode.None
                ? Visibility.Collapsed
                : Visibility.Visible;
            BwToningStrengthControl.Value = bwToning.ClampedStrength;
            BwToningShadowHueControl.Value = bwToning.ShadowHue;
            BwToningHighlightHueControl.Value = bwToning.HighlightHue;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            BwToningHeaderButton, BwToningChevron, BwToningControls, expanded);

    private void OnBwToningModeChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing ||
            BwToningModeSelector.SelectedItem is not ComboBoxItem { Tag: string tag } ||
            !Enum.TryParse(tag, out Catalog.BwToningMode mode))
        {
            return;
        }
        if (panel.Color.SetBwToningMode(mode) == LibraryFrameError.None)
        {
            RefreshRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnBwToningValueChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetBwToning(panel.Color.BwToning with
            {
                Strength = BwToningStrengthControl.Value,
                ShadowHue = BwToningRecipe.NormalizeHue(BwToningShadowHueControl.Value),
                HighlightHue = BwToningRecipe.NormalizeHue(BwToningHighlightHueControl.Value),
            }) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnBwToningResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || panel.Color.ResetBwToning() != LibraryFrameError.None)
        {
            return;
        }
        RefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnInspectorSectionHeaderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnInspectorSectionExpansionRequested(
        object? sender,
        DisclosureExpansionRequestedEventArgs args)
    {
        _ = sender;
        ExpansionRequested?.Invoke(this, args);
    }
}
