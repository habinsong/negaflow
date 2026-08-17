using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>원색 색상·채도 보정입니다.</summary>
public sealed partial class DevelopCalibrationSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopCalibrationSection() => InitializeComponent();

    public event EventHandler? PreviewRequested;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void ConfigureRanges(double toneControl)
    {
        foreach (InspectorSlider slider in new[]
                 {
                     RedPrimaryHueControl,
                     RedPrimarySaturationControl,
                     GreenPrimaryHueControl,
                     GreenPrimarySaturationControl,
                     BluePrimaryHueControl,
                     BluePrimarySaturationControl,
                 })
        {
            slider.Minimum = -toneControl;
            slider.Maximum = toneControl;
        }
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            CalibrationSection,
            CalibrationHeaderButton,
            CalibrationSectionTitleText,
            CalibrationResetButton,
            AppResources.Get("developSectionCalibration", "Text"));
        RedPrimaryText.Text = AppResources.Get("developCalibrationRedPrimary", "Text");
        GreenPrimaryText.Text = AppResources.Get("developCalibrationGreenPrimary", "Text");
        BluePrimaryText.Text = AppResources.Get("developCalibrationBluePrimary", "Text");
        string hue = AppResources.Get("developCalibrationHue", "Text");
        string saturation = AppResources.Get("developCalibrationSaturation", "Text");
        RedPrimaryHueControl.Label = hue;
        GreenPrimaryHueControl.Label = hue;
        BluePrimaryHueControl.Label = hue;
        RedPrimarySaturationControl.Label = saturation;
        GreenPrimarySaturationControl.Label = saturation;
        BluePrimarySaturationControl.Label = saturation;
    }

    public void Show(DevelopPanelState hostPanel)
    {
        PrimaryCalibrationRecipe calibration = hostPanel.Color.PrimaryCalibration;
        isSynchronizing = true;
        try
        {
            RedPrimaryHueControl.Value = calibration.RedHue;
            RedPrimarySaturationControl.Value = calibration.RedSaturation;
            GreenPrimaryHueControl.Value = calibration.GreenHue;
            GreenPrimarySaturationControl.Value = calibration.GreenSaturation;
            BluePrimaryHueControl.Value = calibration.BlueHue;
            BluePrimarySaturationControl.Value = calibration.BlueSaturation;
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
                     RedPrimaryHueControl,
                     RedPrimarySaturationControl,
                     GreenPrimaryHueControl,
                     GreenPrimarySaturationControl,
                     BluePrimaryHueControl,
                     BluePrimarySaturationControl,
                 })
        {
            slider.IsEnabled = enabled;
        }
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            CalibrationHeaderButton, CalibrationChevron, CalibrationControls, expanded);

    private void OnPrimaryCalibrationChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetPrimaryCalibration(new PrimaryCalibrationRecipe(
                RedPrimaryHueControl.Value,
                RedPrimarySaturationControl.Value,
                GreenPrimaryHueControl.Value,
                GreenPrimarySaturationControl.Value,
                BluePrimaryHueControl.Value,
                BluePrimarySaturationControl.Value)) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnCalibrationResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Color.ResetPrimaryCalibration());
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
