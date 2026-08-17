using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS 색상 섹션의 다섯 축입니다. 원색 세 축은 이 섹션에 없으므로 지금 값을 그대로 둡니다.
/// </summary>
public sealed partial class DevelopColorSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopColorSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            ColorSection,
            ColorHeaderButton,
            ColorSectionTitleText,
            ColorResetButton,
            AppResources.Get("developSectionColor", "Text"));
        WarmthControl.Label = AppResources.Get("developWarmth", "Text");
        TintControl.Label = AppResources.Get("developTint", "Text");
        VibranceControl.Label = AppResources.Get("developVibrance", "Text");
        SaturationControl.Label = AppResources.Get("developSaturation", "Text");
        ColorDepthControl.Label = AppResources.Get("developColorDepth", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        ColorModelRecipe colorModel = hostPanel.Color.ColorModel;
        isSynchronizing = true;
        try
        {
            WarmthControl.Value = colorModel.Warmth;
            TintControl.Value = colorModel.Tint;
            VibranceControl.Value = colorModel.Vibrance;
            SaturationControl.Value = colorModel.Saturation;
            ColorDepthControl.Value = colorModel.ColorDepth;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            ColorHeaderButton, ColorChevron, ColorControls, expanded);

    private void OnColorModelChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetColorModel(panel.Color.ColorModel with
            {
                Warmth = WarmthControl.Value,
                Tint = TintControl.Value,
                Vibrance = VibranceControl.Value,
                Saturation = SaturationControl.Value,
                ColorDepth = ColorDepthControl.Value,
            }) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnColorResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Color.ResetColor());
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
