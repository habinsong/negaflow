using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>노출과 기본 톤 슬라이더입니다.</summary>
public sealed partial class DevelopToneSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopToneSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void ConfigureRanges(double exposureStops, double toneControl)
    {
        ExposureControl.Minimum = -exposureStops;
        ExposureControl.Maximum = exposureStops;
        foreach (InspectorSlider slider in new[]
                 {
                     ContrastControl,
                     HighlightsControl,
                     ShadowsControl,
                     WhitesControl,
                     BlacksControl,
                     DensityControl,
                 })
        {
            slider.Minimum = -toneControl;
            slider.Maximum = toneControl;
        }
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            BasicToneSection,
            BasicToneHeaderButton,
            BasicToneSectionTitleText,
            BasicToneResetButton,
            AppResources.Get("developSectionBasicTone", "Text"));
        ExposureControl.Label = AppResources.Get("developExposure", "Text");
        ContrastControl.Label = AppResources.Get("developContrast", "Text");
        HighlightsControl.Label = AppResources.Get("developHighlights", "Text");
        ShadowsControl.Label = AppResources.Get("developShadows", "Text");
        WhitesControl.Label = AppResources.Get("developWhites", "Text");
        BlacksControl.Label = AppResources.Get("developBlacks", "Text");
        DensityControl.Label = AppResources.Get("developDensity", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            ExposureControl.Value = hostPanel.Tone.Exposure;
            ContrastControl.Value = hostPanel.Tone.Contrast;
            HighlightsControl.Value = hostPanel.Tone.Highlights;
            ShadowsControl.Value = hostPanel.Tone.Shadows;
            WhitesControl.Value = hostPanel.Tone.Whites;
            BlacksControl.Value = hostPanel.Tone.Blacks;
            DensityControl.Value = hostPanel.Tone.Density;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    public void SetEnabled(bool enabled)
    {
        foreach (InspectorSlider slider in new[]
                 {
                     ExposureControl,
                     ContrastControl,
                     HighlightsControl,
                     ShadowsControl,
                     WhitesControl,
                     BlacksControl,
                     DensityControl,
                 })
        {
            slider.IsEnabled = enabled;
        }
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            BasicToneHeaderButton, BasicToneChevron, BasicToneControls, expanded);

    private void OnExposureChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        panel.Tone.SetExposure(args.Value);
        PreviewRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnBasicToneChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        if (panel is null || isSynchronizing)
        {
            return;
        }

        LibraryFrameError error = sender switch
        {
            InspectorSlider control when ReferenceEquals(control, ContrastControl) =>
                panel.Tone.SetContrast(args.Value),
            InspectorSlider control when ReferenceEquals(control, HighlightsControl) =>
                panel.Tone.SetHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, ShadowsControl) =>
                panel.Tone.SetShadows(args.Value),
            InspectorSlider control when ReferenceEquals(control, WhitesControl) =>
                panel.Tone.SetWhites(args.Value),
            InspectorSlider control when ReferenceEquals(control, BlacksControl) =>
                panel.Tone.SetBlacks(args.Value),
            InspectorSlider control when ReferenceEquals(control, DensityControl) =>
                panel.Tone.SetDensity(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnBasicToneResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Tone.ResetBasicTone());
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
