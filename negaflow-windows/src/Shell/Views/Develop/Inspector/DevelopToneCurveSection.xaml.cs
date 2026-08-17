using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>네 축 톤 커브와 점 커브 편집기입니다.</summary>
public sealed partial class DevelopToneCurveSection : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopToneCurveSection() => InitializeComponent();

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
                     CurveHighlightsControl,
                     CurveLightsControl,
                     CurveDarksControl,
                     CurveShadowsControl,
                 })
        {
            slider.Minimum = -toneControl;
            slider.Maximum = toneControl;
        }
    }

    public void Localize()
    {
        DevelopInspectorSectionChrome.Localize(
            ToneCurveSection,
            ToneCurveHeaderButton,
            ToneCurveSectionTitleText,
            ToneCurveResetButton,
            AppResources.Get("developSectionToneCurve", "Text"));
        CurveHighlightsControl.Label = AppResources.Get("developHighlights", "Text");
        CurveLightsControl.Label = AppResources.Get("developLights", "Text");
        CurveDarksControl.Label = AppResources.Get("developDarks", "Text");
        CurveShadowsControl.Label = AppResources.Get("developShadows", "Text");
    }

    public void Show(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            CurveHighlightsControl.Value = hostPanel.Tone.CurveHighlights;
            CurveLightsControl.Value = hostPanel.Tone.CurveLights;
            CurveDarksControl.Value = hostPanel.Tone.CurveDarks;
            CurveShadowsControl.Value = hostPanel.Tone.CurveShadows;
            PointCurveEditor.Curves = hostPanel.Color.PointCurves;
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
                     CurveHighlightsControl,
                     CurveLightsControl,
                     CurveDarksControl,
                     CurveShadowsControl,
                 })
        {
            slider.IsEnabled = enabled;
        }
        PointCurveEditor.IsEnabled = enabled;
    }

    public void ApplyExpanded(bool expanded) =>
        DevelopInspectorSectionChrome.Apply(
            ToneCurveHeaderButton, ToneCurveChevron, ToneCurveControls, expanded);

    private void OnToneCurveChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        if (panel is null || isSynchronizing)
        {
            return;
        }

        LibraryFrameError error = sender switch
        {
            InspectorSlider control when ReferenceEquals(control, CurveHighlightsControl) =>
                panel.Tone.SetCurveHighlights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveLightsControl) =>
                panel.Tone.SetCurveLights(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveDarksControl) =>
                panel.Tone.SetCurveDarks(args.Value),
            InspectorSlider control when ReferenceEquals(control, CurveShadowsControl) =>
                panel.Tone.SetCurveShadows(args.Value),
            _ => LibraryFrameError.InvalidToneValue,
        };
        if (error == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnPointCurvesChanged(object? sender, ToneCurveChangedEventArgs args)
    {
        _ = sender;
        if (panel is null || isSynchronizing)
        {
            return;
        }
        if (panel.Color.SetPointCurves(args.Curves) == LibraryFrameError.None)
        {
            PreviewRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void OnToneCurveResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ResetRequested?.Invoke(this, static state => state.Tone.ResetToneCurve());
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
